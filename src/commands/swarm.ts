import fs from 'node:fs/promises';
import path from 'node:path';
import { loadConfig, resolveAgentConfig } from '../core/config.js';
import { readManifest, updateManifest, resolveWorktree } from '../core/manifest.js';
import { getRepoRoot, getCurrentBranch, createWorktree } from '../core/worktree.js';
import { setupWorktreeEnv } from '../core/env.js';
import { renderTemplate, type TemplateContext } from '../core/template.js';
import { loadSwarm, type SwarmAgentEntry, type SwarmTemplate } from '../core/swarm.js';
import { spawnAgent } from '../core/agent.js';
import * as tmux from '../core/tmux.js';
import { openTerminalWindow } from '../core/terminal.js';
import { worktreeId as genWorktreeId, agentId as genAgentId, sessionId as genSessionId } from '../lib/id.js';
import { resultFile, promptsDir, manifestPath } from '../lib/paths.js';
import { PgError, NotInitializedError, WorktreeNotFoundError } from '../lib/errors.js';
import { output, success, info } from '../lib/output.js';
import type { Config } from '../types/config.js';
import type { WorktreeEntry, AgentEntry } from '../types/manifest.js';

export interface SwarmOptions {
  worktree?: string;
  var?: string[];
  name?: string;
  base?: string;
  open?: boolean;
  json?: boolean;
}

export async function swarmCommand(templateName: string, options: SwarmOptions): Promise<void> {
  const projectRoot = await getRepoRoot();
  const config = await loadConfig(projectRoot);

  // Verify initialized
  try {
    await fs.access(manifestPath(projectRoot));
  } catch {
    throw new NotInitializedError(projectRoot);
  }

  // Load swarm template
  const swarm = await loadSwarm(projectRoot, templateName);

  // Parse user vars
  const userVars = parseVars(options.var ?? []);

  if (options.worktree) {
    await swarmIntoExistingWorktree(projectRoot, config, swarm, options, userVars);
  } else if (swarm.strategy === 'isolated') {
    await swarmIsolated(projectRoot, config, swarm, options, userVars);
  } else {
    await swarmShared(projectRoot, config, swarm, options, userVars);
  }
}

function parseVars(vars: string[]): Record<string, string> {
  const result: Record<string, string> = {};
  for (const v of vars) {
    const eqIdx = v.indexOf('=');
    if (eqIdx < 1) {
      throw new PgError(`Invalid --var format: "${v}" — expected KEY=value`, 'INVALID_ARGS');
    }
    result[v.slice(0, eqIdx)] = v.slice(eqIdx + 1);
  }
  return result;
}

async function loadPromptFile(projectRoot: string, promptName: string): Promise<string> {
  const filePath = path.join(promptsDir(projectRoot), `${promptName}.md`);
  try {
    return await fs.readFile(filePath, 'utf-8');
  } catch {
    throw new PgError(`Prompt file not found: ${promptName}.md in .pg/prompts/`, 'INVALID_ARGS');
  }
}

interface SpawnSwarmAgentOptions {
  projectRoot: string;
  config: Config;
  swarmAgent: SwarmAgentEntry;
  wtPath: string;
  branchName: string;
  tmuxTarget: string;
  taskName: string;
  userVars: Record<string, string>;
}

async function spawnSwarmAgent(opts: SpawnSwarmAgentOptions): Promise<AgentEntry> {
  const { projectRoot, config, swarmAgent, wtPath, branchName, tmuxTarget, taskName, userVars } = opts;
  const agentConfig = resolveAgentConfig(config, swarmAgent.agent);
  const aId = genAgentId();

  const promptContent = await loadPromptFile(projectRoot, swarmAgent.prompt);
  const ctx: TemplateContext = {
    WORKTREE_PATH: wtPath,
    BRANCH: branchName,
    AGENT_ID: aId,
    RESULT_FILE: resultFile(projectRoot, aId),
    PROJECT_ROOT: projectRoot,
    TASK_NAME: taskName,
    ...userVars,
    ...(swarmAgent.vars ?? {}),
  };
  const renderedPrompt = renderTemplate(promptContent, ctx);

  return spawnAgent({
    agentId: aId,
    agentConfig,
    prompt: renderedPrompt,
    worktreePath: wtPath,
    tmuxTarget,
    projectRoot,
    branch: branchName,
    sessionId: genSessionId(),
  });
}

async function swarmShared(
  projectRoot: string,
  config: Config,
  swarm: SwarmTemplate,
  options: SwarmOptions,
  userVars: Record<string, string>,
): Promise<void> {
  const baseBranch = options.base ?? await getCurrentBranch(projectRoot);
  const wtId = genWorktreeId();
  const name = options.name ?? swarm.name;
  const branchName = `ppg/${name}`;

  info(`Creating worktree ${wtId} on branch ${branchName}`);
  const wtPath = await createWorktree(projectRoot, wtId, {
    branch: branchName,
    base: baseBranch,
  });

  await setupWorktreeEnv(projectRoot, wtPath, config);

  const sessionName = config.sessionName;
  await tmux.ensureSession(sessionName);
  const windowTarget = await tmux.createWindow(sessionName, name, wtPath);

  const agents: AgentEntry[] = [];
  for (let i = 0; i < swarm.agents.length; i++) {
    const target = i === 0
      ? windowTarget
      : await tmux.createWindow(sessionName, `${name}-${i}`, wtPath);

    const agentEntry = await spawnSwarmAgent({
      projectRoot, config, swarmAgent: swarm.agents[i],
      wtPath, branchName, tmuxTarget: target, taskName: name, userVars,
    });
    agents.push(agentEntry);
  }

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

  if (options.open !== false) {
    openTerminalWindow(sessionName, windowTarget, name).catch(() => {});
  }

  outputResult(options.json, swarm, wtId, name, branchName, wtPath, windowTarget, agents);
}

async function swarmIsolated(
  projectRoot: string,
  config: Config,
  swarm: SwarmTemplate,
  options: SwarmOptions,
  userVars: Record<string, string>,
): Promise<void> {
  const baseBranch = options.base ?? await getCurrentBranch(projectRoot);
  const baseName = options.name ?? swarm.name;
  const sessionName = config.sessionName;
  await tmux.ensureSession(sessionName);

  const worktrees: Array<{ id: string; name: string; branch: string; path: string; tmuxWindow: string }> = [];
  const allAgents: AgentEntry[] = [];

  const usedNames = new Set<string>();
  for (const swarmAgent of swarm.agents) {
    const wtId = genWorktreeId();
    let wtName = `${baseName}-${swarmAgent.prompt}`;
    if (usedNames.has(wtName)) {
      let suffix = 2;
      while (usedNames.has(`${wtName}-${suffix}`)) suffix++;
      wtName = `${wtName}-${suffix}`;
    }
    usedNames.add(wtName);
    const branchName = `ppg/${wtName}`;

    info(`Creating worktree ${wtId} on branch ${branchName}`);
    const wtPath = await createWorktree(projectRoot, wtId, {
      branch: branchName,
      base: baseBranch,
    });

    await setupWorktreeEnv(projectRoot, wtPath, config);
    const windowTarget = await tmux.createWindow(sessionName, wtName, wtPath);

    const agentEntry = await spawnSwarmAgent({
      projectRoot, config, swarmAgent,
      wtPath, branchName, tmuxTarget: windowTarget, taskName: wtName, userVars,
    });

    const worktreeEntry: WorktreeEntry = {
      id: wtId,
      name: wtName,
      path: wtPath,
      branch: branchName,
      baseBranch,
      status: 'active',
      tmuxWindow: windowTarget,
      agents: { [agentEntry.id]: agentEntry },
      createdAt: new Date().toISOString(),
    };

    await updateManifest(projectRoot, (m) => {
      m.worktrees[wtId] = worktreeEntry;
      return m;
    });

    if (options.open !== false) {
      openTerminalWindow(sessionName, windowTarget, wtName).catch(() => {});
    }

    worktrees.push({ id: wtId, name: wtName, branch: branchName, path: wtPath, tmuxWindow: windowTarget });
    allAgents.push(agentEntry);
  }

  if (options.json) {
    output({
      success: true,
      swarm: swarm.name,
      strategy: 'isolated',
      worktrees: worktrees.map((wt, i) => ({
        ...wt,
        agents: [{ id: allAgents[i].id, tmuxTarget: allAgents[i].tmuxTarget, sessionId: allAgents[i].sessionId }],
      })),
    }, true);
  } else {
    success(`Swarm "${swarm.name}" spawned ${swarm.agents.length} agent(s) in isolated worktrees`);
    for (let i = 0; i < worktrees.length; i++) {
      info(`  ${worktrees[i].name} (${worktrees[i].id}) → agent ${allAgents[i].id}`);
    }
  }
}

async function swarmIntoExistingWorktree(
  projectRoot: string,
  config: Config,
  swarm: SwarmTemplate,
  options: SwarmOptions,
  userVars: Record<string, string>,
): Promise<void> {
  const manifest = await readManifest(projectRoot);
  const wt = resolveWorktree(manifest, options.worktree!);

  if (!wt) throw new WorktreeNotFoundError(options.worktree!);

  const sessionName = config.sessionName;

  // Lazily create tmux window if worktree has none
  let windowTarget = wt.tmuxWindow;
  if (!windowTarget) {
    await tmux.ensureSession(sessionName);
    windowTarget = await tmux.createWindow(sessionName, wt.name, wt.path);
  }

  const agents: AgentEntry[] = [];
  for (let i = 0; i < swarm.agents.length; i++) {
    const target = i === 0
      ? windowTarget
      : await tmux.createWindow(sessionName, `${wt.name}-${swarm.name}-${i}`, wt.path);

    const agentEntry = await spawnSwarmAgent({
      projectRoot, config, swarmAgent: swarm.agents[i],
      wtPath: wt.path, branchName: wt.branch, tmuxTarget: target, taskName: wt.name, userVars,
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

  if (options.open !== false) {
    openTerminalWindow(sessionName, windowTarget, wt.name).catch(() => {});
  }

  outputResult(options.json, swarm, wt.id, wt.name, wt.branch, wt.path, windowTarget, agents);
}

function outputResult(
  json: boolean | undefined,
  swarm: SwarmTemplate,
  wtId: string,
  name: string,
  branch: string,
  wtPath: string,
  tmuxWindow: string,
  agents: AgentEntry[],
): void {
  if (json) {
    output({
      success: true,
      swarm: swarm.name,
      strategy: swarm.strategy,
      worktree: { id: wtId, name, branch, path: wtPath, tmuxWindow },
      agents: agents.map((a) => ({ id: a.id, tmuxTarget: a.tmuxTarget, sessionId: a.sessionId })),
    }, true);
  } else {
    success(`Swarm "${swarm.name}" spawned ${agents.length} agent(s) in worktree ${wtId}`);
    for (const a of agents) {
      info(`  Agent ${a.id} → ${a.tmuxTarget}`);
    }
    info(`Attach: ppg attach ${wtId}`);
  }
}
