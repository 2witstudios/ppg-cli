import fs from 'node:fs/promises';
import { loadConfig, resolveAgentConfig } from '../core/config.js';
import { readManifest, updateManifest, resolveWorktree } from '../core/manifest.js';
import { getRepoRoot, getCurrentBranch, createWorktree } from '../core/worktree.js';
import { setupWorktreeEnv } from '../core/env.js';
import { loadTemplate, renderTemplate, type TemplateContext } from '../core/template.js';
import { spawnAgent } from '../core/agent.js';
import * as tmux from '../core/tmux.js';
import { openTerminalWindow } from '../core/terminal.js';
import { worktreeId as genWorktreeId, agentId as genAgentId, sessionId as genSessionId } from '../lib/id.js';
import { resultFile, manifestPath } from '../lib/paths.js';
import { PgError, NotInitializedError, WorktreeNotFoundError } from '../lib/errors.js';
import { output, success, info } from '../lib/output.js';
import { normalizeName } from '../lib/name.js';
import type { WorktreeEntry, AgentEntry } from '../types/manifest.js';

export interface SpawnOptions {
  name?: string;
  agent?: string;
  prompt?: string;
  promptFile?: string;
  template?: string;
  var?: string[];
  base?: string;
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

  // Resolve prompt
  const promptText = await resolvePrompt(options, projectRoot);

  if (options.worktree) {
    // Add agent(s) to existing worktree
    await spawnIntoExistingWorktree(
      projectRoot,
      config,
      agentConfig,
      options.worktree,
      promptText,
      count,
      options,
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
    );
  }
}

async function resolvePrompt(options: SpawnOptions, projectRoot: string): Promise<string> {
  if (options.prompt) return options.prompt;

  if (options.promptFile) {
    return fs.readFile(options.promptFile, 'utf-8');
  }

  if (options.template) {
    const templateContent = await loadTemplate(projectRoot, options.template);
    const vars: Record<string, string> = {};
    for (const v of options.var ?? []) {
      const eqIdx = v.indexOf('=');
      if (eqIdx < 1) {
        throw new PgError(`Invalid --var format: "${v}" — expected KEY=value`, 'INVALID_ARGS');
      }
      vars[v.slice(0, eqIdx)] = v.slice(eqIdx + 1);
    }
    // Template will be fully rendered later with worktree context
    return templateContent;
  }

  throw new PgError('One of --prompt, --prompt-file, or --template is required', 'INVALID_ARGS');
}

async function spawnNewWorktree(
  projectRoot: string,
  config: import('../types/config.js').Config,
  agentConfig: import('../types/config.js').AgentConfig,
  promptText: string,
  count: number,
  options: SpawnOptions,
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

  // Ensure tmux session (use config directly instead of re-reading manifest)
  const sessionName = config.sessionName;
  await tmux.ensureSession(sessionName);

  // Create tmux window
  const windowTarget = await tmux.createWindow(sessionName, name, wtPath);

  // Spawn agents — one tmux window per agent (default), or split panes (--split)
  const agents: AgentEntry[] = [];
  for (let i = 0; i < count; i++) {
    const aId = genAgentId();
    let target: string;

    if (i === 0) {
      // First agent uses the window already created for the worktree
      target = windowTarget;
    } else if (options.split) {
      // --split: additional agents share the same window as split panes
      const direction = i % 2 === 1 ? 'horizontal' : 'vertical';
      const pane = await tmux.splitPane(windowTarget, direction, wtPath);
      target = pane.target;
    } else {
      // Default: each additional agent gets its own tmux window
      target = await tmux.createWindow(sessionName, `${name}-${i}`, wtPath);
    }

    // Render template variables if present
    const ctx: TemplateContext = {
      WORKTREE_PATH: wtPath,
      BRANCH: branchName,
      AGENT_ID: aId,
      RESULT_FILE: resultFile(projectRoot, aId),
      PROJECT_ROOT: projectRoot,
      TASK_NAME: name,
      PROMPT: promptText,
    };

    // Parse user vars
    for (const v of options.var ?? []) {
      const eqIdx = v.indexOf('=');
      if (eqIdx < 1) {
        throw new PgError(`Invalid --var format: "${v}" — expected KEY=value`, 'INVALID_ARGS');
      }
      ctx[v.slice(0, eqIdx)] = v.slice(eqIdx + 1);
    }

    const renderedPrompt = renderTemplate(promptText, ctx);

    const agentEntry = await spawnAgent({
      agentId: aId,
      agentConfig,
      prompt: renderedPrompt,
      worktreePath: wtPath,
      tmuxTarget: target,
      projectRoot,
      branch: branchName,
      sessionId: genSessionId(),
    });

    agents.push(agentEntry);
  }

  // Update manifest
  const worktreeEntry: WorktreeEntry = {
    id: wtId,
    name,
    path: wtPath,
    branch: branchName,
    baseBranch,
    status: 'active',
    tmuxWindow: windowTarget,
    agents: Object.fromEntries(agents.map((a) => [a.id, a])),
    createdAt: new Date().toISOString(),
  };

  await updateManifest(projectRoot, (m) => {
    m.worktrees[wtId] = worktreeEntry;
    return m;
  });

  // Only open Terminal window when explicitly requested via --open (fire-and-forget)
  if (options.open === true) {
    openTerminalWindow(sessionName, windowTarget, name).catch(() => {});
  }

  if (options.json) {
    output({
      success: true,
      worktree: {
        id: wtId,
        name,
        branch: branchName,
        path: wtPath,
        tmuxWindow: windowTarget,
      },
      agents: agents.map((a) => ({
        id: a.id,
        tmuxTarget: a.tmuxTarget,
        sessionId: a.sessionId,
      })),
    }, true);
  } else {
    success(`Spawned worktree ${wtId} with ${agents.length} agent(s)`);
    for (const a of agents) {
      info(`  Agent ${a.id} → ${a.tmuxTarget}`);
    }
    info(`Attach: ppg attach ${wtId}`);
  }
}

async function spawnIntoExistingWorktree(
  projectRoot: string,
  config: import('../types/config.js').Config,
  agentConfig: import('../types/config.js').AgentConfig,
  worktreeRef: string,
  promptText: string,
  count: number,
  options: SpawnOptions,
): Promise<void> {
  const manifest = await readManifest(projectRoot);
  const wt = resolveWorktree(manifest, worktreeRef);

  if (!wt) throw new WorktreeNotFoundError(worktreeRef);

  // Lazily create tmux window if worktree has none (standalone worktree)
  let windowTarget = wt.tmuxWindow;
  if (!windowTarget) {
    await tmux.ensureSession(manifest.sessionName);
    windowTarget = await tmux.createWindow(manifest.sessionName, wt.name, wt.path);
  }

  const agents: AgentEntry[] = [];
  for (let i = 0; i < count; i++) {
    const aId = genAgentId();

    let target: string;
    if (i === 0 && options.split) {
      // First agent reuses the existing window pane
      target = windowTarget;
    } else if (options.split) {
      // --split: additional agents share the same window as split panes
      const direction = i % 2 === 1 ? 'horizontal' : 'vertical';
      const pane = await tmux.splitPane(windowTarget, direction, wt.path);
      target = pane.target;
    } else {
      // Default: every agent gets its own tmux window
      target = await tmux.createWindow(manifest.sessionName, `${wt.name}-agent-${i}`, wt.path);
    }

    const ctx: TemplateContext = {
      WORKTREE_PATH: wt.path,
      BRANCH: wt.branch,
      AGENT_ID: aId,
      RESULT_FILE: resultFile(projectRoot, aId),
      PROJECT_ROOT: projectRoot,
      TASK_NAME: wt.name,
      PROMPT: promptText,
    };

    for (const v of options.var ?? []) {
      const eqIdx = v.indexOf('=');
      if (eqIdx < 1) {
        throw new PgError(`Invalid --var format: "${v}" — expected KEY=value`, 'INVALID_ARGS');
      }
      ctx[v.slice(0, eqIdx)] = v.slice(eqIdx + 1);
    }

    const renderedPrompt = renderTemplate(promptText, ctx);

    const agentEntry = await spawnAgent({
      agentId: aId,
      agentConfig,
      prompt: renderedPrompt,
      worktreePath: wt.path,
      tmuxTarget: target,
      projectRoot,
      branch: wt.branch,
      sessionId: genSessionId(),
    });

    agents.push(agentEntry);
  }

  await updateManifest(projectRoot, (m) => {
    const mWt = m.worktrees[wt.id];
    if (!mWt.tmuxWindow) {
      mWt.tmuxWindow = windowTarget;
    }
    for (const a of agents) {
      mWt.agents[a.id] = a;
    }
    return m;
  });

  // Only open Terminal window when explicitly requested via --open (fire-and-forget)
  if (options.open === true) {
    openTerminalWindow(manifest.sessionName, windowTarget, wt.name).catch(() => {});
  }

  if (options.json) {
    output({
      success: true,
      worktree: {
        id: wt.id,
        name: wt.name,
        branch: wt.branch,
        path: wt.path,
        tmuxWindow: windowTarget,
      },
      agents: agents.map((a) => ({ id: a.id, tmuxTarget: a.tmuxTarget, sessionId: a.sessionId })),
    }, true);
  } else {
    success(`Added ${agents.length} agent(s) to worktree ${wt.id}`);
    for (const a of agents) {
      info(`  Agent ${a.id} → ${a.tmuxTarget}`);
    }
  }
}
