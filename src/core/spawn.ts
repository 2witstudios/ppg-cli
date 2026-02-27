import { loadConfig, resolveAgentConfig } from './config.js';
import { requireManifest, updateManifest } from './manifest.js';
import { getCurrentBranch, createWorktree } from './worktree.js';
import { setupWorktreeEnv } from './env.js';
import { loadTemplate, renderTemplate, type TemplateContext } from './template.js';
import { spawnAgent } from './agent.js';
import * as tmux from './tmux.js';
import { worktreeId as genWorktreeId, agentId as genAgentId, sessionId as genSessionId } from '../lib/id.js';
import { PpgError } from '../lib/errors.js';
import { normalizeName } from '../lib/name.js';
import type { WorktreeEntry, AgentEntry } from '../types/manifest.js';
import type { AgentConfig } from '../types/config.js';

// ─── Agent Batch Spawning ────────────────────────────────────────────────────

export interface SpawnBatchOptions {
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

export async function spawnAgentBatch(opts: SpawnBatchOptions): Promise<AgentEntry[]> {
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

// ─── New Worktree Spawn ──────────────────────────────────────────────────────

export interface SpawnNewWorktreeOptions {
  projectRoot: string;
  name: string;
  promptText: string;
  userVars?: Record<string, string>;
  agentName?: string;
  baseBranch?: string;
  count?: number;
  split?: boolean;
}

export interface SpawnNewWorktreeResult {
  worktreeId: string;
  name: string;
  branch: string;
  path: string;
  tmuxWindow: string;
  agents: AgentEntry[];
}

export async function spawnNewWorktree(
  opts: SpawnNewWorktreeOptions,
): Promise<SpawnNewWorktreeResult> {
  const { projectRoot } = opts;
  const config = await loadConfig(projectRoot);
  const agentConfig = resolveAgentConfig(config, opts.agentName);
  const count = opts.count ?? 1;
  const userVars = opts.userVars ?? {};
  const manifest = await requireManifest(projectRoot);
  const sessionName = manifest.sessionName;

  const baseBranch = opts.baseBranch ?? await getCurrentBranch(projectRoot);
  const wtId = genWorktreeId();
  const name = normalizeName(opts.name, wtId);
  const branchName = `ppg/${name}`;

  // Create git worktree
  const wtPath = await createWorktree(projectRoot, wtId, {
    branch: branchName,
    base: baseBranch,
  });

  // Setup env (copy .env, symlink node_modules)
  await setupWorktreeEnv(projectRoot, wtPath, config);

  // Ensure tmux session (manifest is the source of truth for session name)
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

  // Spawn agents
  const agents = await spawnAgentBatch({
    projectRoot,
    agentConfig,
    promptText: opts.promptText,
    userVars,
    count,
    split: opts.split === true,
    worktreePath: wtPath,
    branch: branchName,
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

  return {
    worktreeId: wtId,
    name,
    branch: branchName,
    path: wtPath,
    tmuxWindow: windowTarget,
    agents,
  };
}

// ─── Prompt Resolution ───────────────────────────────────────────────────────

export interface PromptSource {
  prompt?: string;
  template?: string;
}

export async function resolvePromptText(
  source: PromptSource,
  projectRoot: string,
): Promise<string> {
  if (source.prompt) return source.prompt;

  if (source.template) {
    return loadTemplate(projectRoot, source.template);
  }

  throw new PpgError(
    'Either "prompt" or "template" is required',
    'INVALID_ARGS',
  );
}
