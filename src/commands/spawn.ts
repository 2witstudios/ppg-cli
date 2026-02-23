import fs from 'node:fs/promises';
import { loadConfig, resolveAgentConfig } from '../core/config.js';
import { readManifest, updateManifest, getWorktree } from '../core/manifest.js';
import { getRepoRoot, getCurrentBranch, createWorktree } from '../core/worktree.js';
import { setupWorktreeEnv } from '../core/env.js';
import { loadTemplate, renderTemplate, type TemplateContext } from '../core/template.js';
import { spawnAgent } from '../core/agent.js';
import * as tmux from '../core/tmux.js';
import { worktreeId as genWorktreeId, agentId as genAgentId } from '../lib/id.js';
import { worktreePath as getWorktreePath } from '../lib/paths.js';
import { resultFile } from '../lib/paths.js';
import { NotInitializedError, WorktreeNotFoundError } from '../lib/errors.js';
import { output, success, info } from '../lib/output.js';
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
  json?: boolean;
}

export async function spawnCommand(options: SpawnOptions): Promise<void> {
  const projectRoot = await getRepoRoot();
  const config = await loadConfig(projectRoot);

  // Verify initialized
  try {
    await readManifest(projectRoot);
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
      const [key, ...rest] = v.split('=');
      vars[key] = rest.join('=');
    }
    // Template will be fully rendered later with worktree context
    return templateContent;
  }

  throw new Error('One of --prompt, --prompt-file, or --template is required');
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
  const name = options.name ?? wtId;
  const branchName = `pg/${name}`;

  // Create git worktree
  info(`Creating worktree ${wtId} on branch ${branchName}`);
  const wtPath = await createWorktree(projectRoot, wtId, {
    branch: branchName,
    base: baseBranch,
  });

  // Setup env
  await setupWorktreeEnv(projectRoot, wtPath, config);

  // Ensure tmux session
  const manifest = await readManifest(projectRoot);
  await tmux.ensureSession(manifest.sessionName);

  // Create tmux window
  const windowTarget = await tmux.createWindow(manifest.sessionName, name, wtPath);

  // Spawn agents
  const agents: AgentEntry[] = [];
  for (let i = 0; i < count; i++) {
    const aId = genAgentId();
    let target = windowTarget;

    if (i > 0) {
      // Split pane for additional agents
      const split = await tmux.splitPane(windowTarget, 'horizontal', wtPath);
      target = split.target;
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
      const [key, ...rest] = v.split('=');
      ctx[key] = rest.join('=');
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
      })),
    }, true);
  } else {
    success(`Spawned worktree ${wtId} with ${agents.length} agent(s)`);
    for (const a of agents) {
      info(`  Agent ${a.id} → ${a.tmuxTarget}`);
    }
    info(`Attach: pg attach ${wtId}`);
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
  const wt = getWorktree(manifest, worktreeRef)
    ?? Object.values(manifest.worktrees).find((w) => w.name === worktreeRef);

  if (!wt) throw new WorktreeNotFoundError(worktreeRef);

  const agents: AgentEntry[] = [];
  for (let i = 0; i < count; i++) {
    const aId = genAgentId();

    const split = await tmux.splitPane(wt.tmuxWindow, 'horizontal', wt.path);

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
      const [key, ...rest] = v.split('=');
      ctx[key] = rest.join('=');
    }

    const renderedPrompt = renderTemplate(promptText, ctx);

    const agentEntry = await spawnAgent({
      agentId: aId,
      agentConfig,
      prompt: renderedPrompt,
      worktreePath: wt.path,
      tmuxTarget: split.target,
      projectRoot,
      branch: wt.branch,
    });

    agents.push(agentEntry);
  }

  await updateManifest(projectRoot, (m) => {
    const mWt = m.worktrees[wt.id];
    for (const a of agents) {
      mWt.agents[a.id] = a;
    }
    return m;
  });

  if (options.json) {
    output({
      success: true,
      worktree: { id: wt.id, name: wt.name },
      agents: agents.map((a) => ({ id: a.id, tmuxTarget: a.tmuxTarget })),
    }, true);
  } else {
    success(`Added ${agents.length} agent(s) to worktree ${wt.id}`);
    for (const a of agents) {
      info(`  Agent ${a.id} → ${a.tmuxTarget}`);
    }
  }
}
