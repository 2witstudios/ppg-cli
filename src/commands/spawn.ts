import fs from 'node:fs/promises';
import { loadConfig, resolveAgentConfig } from '../core/config.js';
import { readManifest, updateManifest, resolveWorktree } from '../core/manifest.js';
import { getRepoRoot, getCurrentBranch, createWorktree, adoptWorktree } from '../core/worktree.js';
import { setupWorktreeEnv } from '../core/env.js';
import { loadTemplate, renderTemplate, type TemplateContext } from '../core/template.js';
import { spawnAgent } from '../core/agent.js';
import * as tmux from '../core/tmux.js';
import { openTerminalWindow } from '../core/terminal.js';
import { worktreeId as genWorktreeId, agentId as genAgentId, sessionId as genSessionId } from '../lib/id.js';
import { manifestPath } from '../lib/paths.js';
import { PpgError, NotInitializedError, WorktreeNotFoundError } from '../lib/errors.js';
import { output, success, info } from '../lib/output.js';
import { normalizeName } from '../lib/name.js';
import { parseVars } from '../lib/vars.js';
import type { WorktreeEntry, AgentEntry } from '../types/manifest.js';
import type { Config, AgentConfig } from '../types/config.js';

export interface SpawnOptions {
  name?: string;
  agent?: string;
  prompt?: string;
  promptFile?: string;
  template?: string;
  var?: string[];
  base?: string;
  branch?: string;
  worktree?: string;
  count?: number;
  split?: boolean;
  open?: boolean;
  json?: boolean;
}

export async function spawnCommand(options: SpawnOptions): Promise<void> {
  const projectRoot = await getRepoRoot();
  const config = await loadConfig(projectRoot);

  // Verify initialized (lightweight file check instead of full manifest read)
  try {
    await fs.access(manifestPath(projectRoot));
  } catch {
    throw new NotInitializedError(projectRoot);
  }

  const agentConfig = resolveAgentConfig(config, options.agent);
  const count = options.count ?? 1;

  // Validate vars early — before any side effects (worktree/tmux creation)
  const userVars = parseVars(options.var ?? []);

  // Resolve prompt
  const promptText = await resolvePrompt(options, projectRoot);

  // Validate conflicting flags
  if (options.branch && options.worktree) {
    throw new PpgError('--branch and --worktree are mutually exclusive', 'INVALID_ARGS');
  }
  if (options.branch && options.base) {
    throw new PpgError('--branch and --base are mutually exclusive (--base is for new branches)', 'INVALID_ARGS');
  }

  if (options.worktree) {
    // Add agent(s) to existing worktree
    await spawnIntoExistingWorktree(
      projectRoot,
      agentConfig,
      options.worktree,
      promptText,
      count,
      options,
      userVars,
    );
  } else if (options.branch) {
    // Create worktree from existing branch
    await spawnOnExistingBranch(
      projectRoot,
      config,
      agentConfig,
      options.branch,
      promptText,
      count,
      options,
      userVars,
    );
  } else {
    // Create new worktree + agent(s)
    await spawnNewWorktree(
      projectRoot,
      config,
      agentConfig,
      promptText,
      count,
      options,
      userVars,
    );
  }
}

async function resolvePrompt(options: SpawnOptions, projectRoot: string): Promise<string> {
  if (options.prompt) return options.prompt;

  if (options.promptFile) {
    return fs.readFile(options.promptFile, 'utf-8');
  }

  if (options.template) {
    return loadTemplate(projectRoot, options.template);
  }

  throw new PpgError('One of --prompt, --prompt-file, or --template is required', 'INVALID_ARGS');
}

interface SpawnBatchOptions {
  projectRoot: string;
  agentConfig: AgentConfig;
  promptText: string;
  userVars: Record<string, string>;
  count: number;
  split: boolean;
  worktreePath: string;
  branch: string;
  taskName: string;
  sessionName: string;
  windowTarget: string;
  windowNamePrefix: string;
  reuseWindowForFirstAgent: boolean;
  onAgentSpawned?: (agent: AgentEntry) => Promise<void>;
}

interface SpawnTargetOptions {
  index: number;
  split: boolean;
  reuseWindowForFirstAgent: boolean;
  windowTarget: string;
  sessionName: string;
  windowNamePrefix: string;
  worktreePath: string;
}

async function resolveAgentTarget(opts: SpawnTargetOptions): Promise<string> {
  if (opts.index === 0 && opts.reuseWindowForFirstAgent) {
    return opts.windowTarget;
  }
  if (opts.split) {
    const direction = opts.index % 2 === 1 ? 'horizontal' : 'vertical';
    const pane = await tmux.splitPane(opts.windowTarget, direction, opts.worktreePath);
    return pane.target;
  }
  return tmux.createWindow(opts.sessionName, `${opts.windowNamePrefix}-${opts.index}`, opts.worktreePath);
}

async function spawnAgentBatch(opts: SpawnBatchOptions): Promise<AgentEntry[]> {
  const agents: AgentEntry[] = [];
  for (let i = 0; i < opts.count; i++) {
    const aId = genAgentId();
    const target = await resolveAgentTarget({
      index: i,
      split: opts.split,
      reuseWindowForFirstAgent: opts.reuseWindowForFirstAgent,
      windowTarget: opts.windowTarget,
      sessionName: opts.sessionName,
      windowNamePrefix: opts.windowNamePrefix,
      worktreePath: opts.worktreePath,
    });

    const ctx: TemplateContext = {
      WORKTREE_PATH: opts.worktreePath,
      BRANCH: opts.branch,
      AGENT_ID: aId,
      PROJECT_ROOT: opts.projectRoot,
      TASK_NAME: opts.taskName,
      PROMPT: opts.promptText,
      ...opts.userVars,
    };

    const agentEntry = await spawnAgent({
      agentId: aId,
      agentConfig: opts.agentConfig,
      prompt: renderTemplate(opts.promptText, ctx),
      worktreePath: opts.worktreePath,
      tmuxTarget: target,
      projectRoot: opts.projectRoot,
      branch: opts.branch,
      sessionId: genSessionId(),
    });

    agents.push(agentEntry);
    if (opts.onAgentSpawned) {
      await opts.onAgentSpawned(agentEntry);
    }
  }

  return agents;
}

interface EmitSpawnResultOptions {
  json: boolean | undefined;
  successMessage: string;
  worktree: {
    id: string;
    name: string;
    branch: string;
    path: string;
    tmuxWindow: string;
  };
  agents: AgentEntry[];
  attachRef?: string;
}

function emitSpawnResult(opts: EmitSpawnResultOptions): void {
  if (opts.json) {
    output({
      success: true,
      worktree: opts.worktree,
      agents: opts.agents.map((a) => ({
        id: a.id,
        tmuxTarget: a.tmuxTarget,
        sessionId: a.sessionId,
      })),
    }, true);
    return;
  }

  success(opts.successMessage);
  for (const a of opts.agents) {
    info(`  Agent ${a.id} → ${a.tmuxTarget}`);
  }
  if (opts.attachRef) {
    info(`Attach: ppg attach ${opts.attachRef}`);
  }
}

async function spawnNewWorktree(
  projectRoot: string,
  config: Config,
  agentConfig: AgentConfig,
  promptText: string,
  count: number,
  options: SpawnOptions,
  userVars: Record<string, string>,
): Promise<void> {
  const baseBranch = options.base ?? await getCurrentBranch(projectRoot);
  const wtId = genWorktreeId();
  const name = options.name ? normalizeName(options.name, wtId) : wtId;
  const branchName = `ppg/${name}`;

  // Create git worktree
  info(`Creating worktree ${wtId} on branch ${branchName}`);
  const wtPath = await createWorktree(projectRoot, wtId, {
    branch: branchName,
    base: baseBranch,
  });

  // Setup env
  await setupWorktreeEnv(projectRoot, wtPath, config);

  // Ensure tmux session (manifest is the source of truth for session name)
  const manifest = await readManifest(projectRoot);
  const sessionName = manifest.sessionName;
  await tmux.ensureSession(sessionName);

  // Create tmux window
  const windowTarget = await tmux.createWindow(sessionName, name, wtPath);

  // Register skeleton worktree in manifest before spawning agents
  // so partial failures leave a record for cleanup
  const worktreeEntry: WorktreeEntry = {
    id: wtId,
    name,
    path: wtPath,
    branch: branchName,
    baseBranch,
    status: 'active',
    tmuxWindow: windowTarget,
    agents: {},
    createdAt: new Date().toISOString(),
  };

  await updateManifest(projectRoot, (m) => {
    m.worktrees[wtId] = worktreeEntry;
    return m;
  });

  // Spawn agents — one tmux window per agent (default), or split panes (--split)
  const agents = await spawnAgentBatch({
    projectRoot,
    agentConfig,
    promptText,
    userVars,
    count,
    split: options.split === true,
    worktreePath: wtPath,
    branch: branchName,
    taskName: name,
    sessionName,
    windowTarget,
    windowNamePrefix: name,
    reuseWindowForFirstAgent: true,
    onAgentSpawned: async (agentEntry) => {
      // Update manifest incrementally after each agent spawn.
      await updateManifest(projectRoot, (m) => {
        if (m.worktrees[wtId]) {
          m.worktrees[wtId].agents[agentEntry.id] = agentEntry;
        }
        return m;
      });
    },
  });

  // Only open Terminal window when explicitly requested via --open (fire-and-forget)
  if (options.open === true) {
    openTerminalWindow(sessionName, windowTarget, name).catch(() => {});
  }

  emitSpawnResult({
    json: options.json,
    successMessage: `Spawned worktree ${wtId} with ${agents.length} agent(s)`,
    worktree: {
      id: wtId,
      name,
      branch: branchName,
      path: wtPath,
      tmuxWindow: windowTarget,
    },
    agents,
    attachRef: wtId,
  });
}

async function spawnOnExistingBranch(
  projectRoot: string,
  config: Config,
  agentConfig: AgentConfig,
  branch: string,
  promptText: string,
  count: number,
  options: SpawnOptions,
  userVars: Record<string, string>,
): Promise<void> {
  const baseBranch = await getCurrentBranch(projectRoot);
  const wtId = genWorktreeId();

  // Derive name from branch if --name not provided (strip ppg/ prefix if present)
  const derivedName = branch.startsWith('ppg/') ? branch.slice(4) : branch;
  const name = options.name ? normalizeName(options.name, wtId) : normalizeName(derivedName, wtId);

  // Create git worktree from existing branch (no -b flag)
  info(`Creating worktree ${wtId} from existing branch ${branch}`);
  const wtPath = await adoptWorktree(projectRoot, wtId, branch);

  // Setup env
  await setupWorktreeEnv(projectRoot, wtPath, config);

  // Ensure tmux session
  const manifest = await readManifest(projectRoot);
  const sessionName = manifest.sessionName;
  await tmux.ensureSession(sessionName);

  // Create tmux window
  const windowTarget = await tmux.createWindow(sessionName, name, wtPath);

  // Register worktree in manifest
  const worktreeEntry: WorktreeEntry = {
    id: wtId,
    name,
    path: wtPath,
    branch,
    baseBranch,
    status: 'active',
    tmuxWindow: windowTarget,
    agents: {},
    createdAt: new Date().toISOString(),
  };

  await updateManifest(projectRoot, (m) => {
    m.worktrees[wtId] = worktreeEntry;
    return m;
  });

  const agents = await spawnAgentBatch({
    projectRoot,
    agentConfig,
    promptText,
    userVars,
    count,
    split: options.split === true,
    worktreePath: wtPath,
    branch,
    taskName: name,
    sessionName,
    windowTarget,
    windowNamePrefix: name,
    reuseWindowForFirstAgent: true,
    onAgentSpawned: async (agentEntry) => {
      await updateManifest(projectRoot, (m) => {
        if (m.worktrees[wtId]) {
          m.worktrees[wtId].agents[agentEntry.id] = agentEntry;
        }
        return m;
      });
    },
  });

  if (options.open === true) {
    openTerminalWindow(sessionName, windowTarget, name).catch(() => {});
  }

  emitSpawnResult({
    json: options.json,
    successMessage: `Spawned worktree ${wtId} from branch ${branch} with ${agents.length} agent(s)`,
    worktree: {
      id: wtId,
      name,
      branch,
      path: wtPath,
      tmuxWindow: windowTarget,
    },
    agents,
    attachRef: wtId,
  });
}

async function spawnIntoExistingWorktree(
  projectRoot: string,
  agentConfig: AgentConfig,
  worktreeRef: string,
  promptText: string,
  count: number,
  options: SpawnOptions,
  userVars: Record<string, string>,
): Promise<void> {
  const manifest = await readManifest(projectRoot);
  const wt = resolveWorktree(manifest, worktreeRef);

  if (!wt) throw new WorktreeNotFoundError(worktreeRef);

  // Lazily create tmux window if worktree has none (standalone worktree)
  let windowTarget = wt.tmuxWindow;
  if (!windowTarget) {
    await tmux.ensureSession(manifest.sessionName);
    windowTarget = await tmux.createWindow(manifest.sessionName, wt.name, wt.path);

    // Persist tmux window before spawning agents so partial failures are tracked.
    await updateManifest(projectRoot, (m) => {
      const mWt = m.worktrees[wt.id];
      if (!mWt) return m;
      mWt.tmuxWindow = windowTarget;
      return m;
    });
  }

  const agents = await spawnAgentBatch({
    projectRoot,
    agentConfig,
    promptText,
    userVars,
    count,
    split: options.split === true,
    worktreePath: wt.path,
    branch: wt.branch,
    taskName: wt.name,
    sessionName: manifest.sessionName,
    windowTarget,
    windowNamePrefix: `${wt.name}-agent`,
    // For existing worktrees, only reuse the primary pane when explicitly splitting.
    reuseWindowForFirstAgent: options.split === true,
    onAgentSpawned: async (agentEntry) => {
      await updateManifest(projectRoot, (m) => {
        const mWt = m.worktrees[wt.id];
        if (!mWt) return m;
        mWt.agents[agentEntry.id] = agentEntry;
        return m;
      });
    },
  });

  // Only open Terminal window when explicitly requested via --open (fire-and-forget)
  if (options.open === true) {
    openTerminalWindow(manifest.sessionName, windowTarget, wt.name).catch(() => {});
  }

  emitSpawnResult({
    json: options.json,
    successMessage: `Added ${agents.length} agent(s) to worktree ${wt.id}`,
    worktree: {
      id: wt.id,
      name: wt.name,
      branch: wt.branch,
      path: wt.path,
      tmuxWindow: windowTarget,
    },
    agents,
  });
}
