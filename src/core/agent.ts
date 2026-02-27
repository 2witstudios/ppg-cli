import fs from 'node:fs/promises';
import { agentPromptFile, agentPromptsDir } from '../lib/paths.js';
import { getBackend } from './backend.js';
import type { PaneInfo } from './process-manager.js';
import { updateManifest } from './manifest.js';
import { PpgError } from '../lib/errors.js';
import { agentId as genAgentId, sessionId as genSessionId } from '../lib/id.js';
import { renderTemplate, type TemplateContext } from './template.js';
import type { AgentEntry, AgentStatus, WorktreeEntry } from '../types/manifest.js';
import type { AgentConfig } from '../types/config.js';

const SHELL_COMMANDS = new Set(['bash', 'zsh', 'sh', 'fish', 'dash', 'tcsh', 'csh']);

export interface SpawnAgentOptions {
  agentId: string;
  agentConfig: AgentConfig;
  prompt: string;
  worktreePath: string;
  tmuxTarget: string;
  projectRoot: string;
  branch: string;
  sessionId?: string;
}

export async function spawnAgent(options: SpawnAgentOptions): Promise<AgentEntry> {
  const {
    agentId,
    agentConfig,
    prompt,
    tmuxTarget,
    projectRoot,
  } = options;

  // Write prompt to file
  const pFile = agentPromptFile(projectRoot, agentId);
  await fs.mkdir(agentPromptsDir(projectRoot), { recursive: true });
  await fs.writeFile(pFile, prompt, 'utf-8');

  // Build and send command
  const command = buildAgentCommand(agentConfig, pFile, options.sessionId);
  await getBackend().sendKeys(tmuxTarget, command);

  return {
    id: agentId,
    name: agentConfig.name,
    agentType: agentConfig.name,
    status: 'running',
    tmuxTarget,
    prompt: prompt.slice(0, 500), // Truncate for manifest storage
    startedAt: new Date().toISOString(),
    ...(options.sessionId ? { sessionId: options.sessionId } : {}),
  };
}

function buildAgentCommand(agentConfig: AgentConfig, promptFilePath: string, sessionId?: string): string {
  // Unset CLAUDECODE so spawned Claude instances don't think they're nested
  const envPrefix = 'unset CLAUDECODE;';
  const { command, promptFlag } = agentConfig;
  // Inject --session-id for Claude-based commands
  const sessionFlag = sessionId && command.includes('claude') ? ` --session-id ${sessionId}` : '';
  // Single-quote the path inside $(cat ...) to handle spaces safely
  const catExpr = `"$(cat '${promptFilePath}')"`;
  if (promptFlag) {
    // Use explicit flag: command --flag "$(cat 'prompt-file')"
    return `${envPrefix} ${command}${sessionFlag} ${promptFlag} ${catExpr}`;
  }
  // Pass prompt as positional argument: command "$(cat 'prompt-file')"
  return `${envPrefix} ${command}${sessionFlag} ${catExpr}`;
}

/**
 * Check agent status by reading live tmux pane state.
 * Every call re-derives status from the pane — no cached terminal states.
 *
 * 1. getPaneInfo() → null → 'gone'
 * 2. pane.isDead → 'exited' (store exitCode)
 * 3. SHELL_COMMANDS.has(pane.currentCommand) → 'idle'
 * 4. otherwise → 'running'
 *
 * @param paneMap Optional pre-fetched pane map from listSessionPanes() for batch queries
 */
export async function checkAgentStatus(
  agent: AgentEntry,
  _projectRoot: string,
  paneMap?: Map<string, PaneInfo>,
): Promise<{ status: AgentStatus; exitCode?: number }> {
  // 1. Check if tmux pane exists (use batch map if available)
  const paneInfo = paneMap
    ? (paneMap.get(agent.tmuxTarget) ?? null)
    : await getBackend().getPaneInfo(agent.tmuxTarget);
  if (!paneInfo) {
    return { status: 'gone' };
  }

  // 2. Check if pane is dead
  if (paneInfo.isDead) {
    return { status: 'exited', exitCode: paneInfo.deadStatus };
  }

  // 3. Check if current command is a shell (agent process exited, returned to shell)
  if (SHELL_COMMANDS.has(paneInfo.currentCommand)) {
    return { status: 'idle' };
  }

  // 4. Still running
  return { status: 'running' };
}

export async function refreshAllAgentStatuses(
  manifest: import('../types/manifest.js').Manifest,
  projectRoot: string,
): Promise<import('../types/manifest.js').Manifest> {
  // Batch-fetch all pane info in a single tmux call
  const paneMap = await getBackend().listSessionPanes(manifest.sessionName);

  // Collect all agents that need checking
  const checks: Array<{ agent: AgentEntry; promise: Promise<{ status: AgentStatus; exitCode?: number }> }> = [];
  for (const wt of Object.values(manifest.worktrees)) {
    for (const agent of Object.values(wt.agents)) {
      checks.push({
        agent,
        promise: checkAgentStatus(agent, projectRoot, paneMap),
      });
    }
  }

  // Run all status checks in parallel
  const results = await Promise.all(checks.map((c) => c.promise));

  // Apply results
  for (let i = 0; i < checks.length; i++) {
    const { agent } = checks[i];
    const { status, exitCode } = results[i];
    agent.status = status;
    if (exitCode !== undefined) agent.exitCode = exitCode;
  }

  // Check worktree directories in parallel
  const wtChecks = Object.values(manifest.worktrees)
    .filter((wt) => wt.status === 'active')
    .map(async (wt) => {
      const exists = await fileExists(wt.path);
      if (!exists) {
        wt.status = 'cleaned';
        for (const agent of Object.values(wt.agents)) {
          agent.status = 'gone';
        }
      }
    });
  await Promise.all(wtChecks);

  return manifest;
}

export interface ResumeAgentOptions {
  agent: AgentEntry;
  worktreeId: string;
  sessionName: string;
  cwd: string;
  windowName: string;
  projectRoot: string;
}

/**
 * Resume a dead agent's session in a new tmux window, updating the manifest.
 * Returns the new tmux target.
 */
export async function resumeAgent(options: ResumeAgentOptions): Promise<string> {
  const { agent, worktreeId, sessionName, cwd, windowName, projectRoot } = options;

  if (!agent.sessionId) {
    throw new PpgError(
      `Agent ${agent.id} has no session ID. Cannot resume agents spawned before session tracking was added.`,
      'NO_SESSION_ID',
    );
  }

  await getBackend().ensureSession(sessionName);
  const newTarget = await getBackend().createWindow(sessionName, windowName, cwd);
  await getBackend().sendKeys(newTarget, `unset CLAUDECODE; claude --resume ${agent.sessionId}`);

  await updateManifest(projectRoot, (m) => {
    const mAgent = m.worktrees[worktreeId]?.agents[agent.id];
    if (mAgent) {
      mAgent.tmuxTarget = newTarget;
      mAgent.status = 'running';
    }
    return m;
  });

  return newTarget;
}

export async function killAgent(agent: AgentEntry): Promise<void> {
  // Check if pane exists before attempting to kill
  const initialInfo = await getBackend().getPaneInfo(agent.tmuxTarget);
  if (!initialInfo || initialInfo.isDead) return;

  // Send Ctrl-C first (pane may die between check and send)
  try {
    await getBackend().sendCtrlC(agent.tmuxTarget);
  } catch {
    // Pane died between check and send — already gone
    return;
  }

  // Wait for graceful shutdown (Claude Code needs more time)
  await new Promise((resolve) => setTimeout(resolve, 2000));

  // Check if still alive
  const paneInfo = await getBackend().getPaneInfo(agent.tmuxTarget);
  if (paneInfo && !paneInfo.isDead) {
    // Kill the pane
    await getBackend().killPane(agent.tmuxTarget);
  }
}

/**
 * Kill multiple agents in parallel: send Ctrl-C to all, wait once, then force-kill survivors.
 */
export async function killAgents(agents: AgentEntry[]): Promise<void> {
  if (agents.length === 0) return;

  // Filter to only agents with live panes
  const alive: AgentEntry[] = [];
  await Promise.all(agents.map(async (a) => {
    const info = await getBackend().getPaneInfo(a.tmuxTarget);
    if (info && !info.isDead) alive.push(a);
  }));
  if (alive.length === 0) return;

  // Send Ctrl-C to all live agents in parallel (catch pane-died-between-check-and-send)
  await Promise.all(alive.map((a) => getBackend().sendCtrlC(a.tmuxTarget).catch(() => {})));

  // Wait for graceful shutdown (Claude Code needs more time)
  await new Promise((resolve) => setTimeout(resolve, 2000));

  // Check and force-kill survivors in parallel
  await Promise.all(alive.map(async (a) => {
    const paneInfo = await getBackend().getPaneInfo(a.tmuxTarget);
    if (paneInfo && !paneInfo.isDead) {
      await getBackend().killPane(a.tmuxTarget);
    }
  }));
}

export interface RestartAgentOptions {
  projectRoot: string;
  agentId: string;
  worktree: WorktreeEntry;
  oldAgent: AgentEntry;
  sessionName: string;
  agentConfig: AgentConfig;
  promptText: string;
}

export interface RestartAgentResult {
  oldAgentId: string;
  newAgentId: string;
  tmuxTarget: string;
  sessionId: string;
  worktreeId: string;
  worktreeName: string;
  branch: string;
  path: string;
}

/**
 * Restart an agent: kill old, spawn new in a fresh tmux window, update manifest.
 */
export async function restartAgent(opts: RestartAgentOptions): Promise<RestartAgentResult> {
  const { projectRoot, worktree: wt, oldAgent, sessionName, agentConfig, promptText } = opts;

  // Kill old agent if still running
  if (oldAgent.status === 'running') {
    await killAgent(oldAgent);
  }

  await getBackend().ensureSession(sessionName);
  const newAgentId = genAgentId();
  const windowTarget = await getBackend().createWindow(sessionName, `${wt.name}-restart`, wt.path);

  const ctx: TemplateContext = {
    WORKTREE_PATH: wt.path,
    BRANCH: wt.branch,
    AGENT_ID: newAgentId,
    PROJECT_ROOT: projectRoot,
    TASK_NAME: wt.name,
    PROMPT: promptText,
  };
  const renderedPrompt = renderTemplate(promptText, ctx);

  const newSessionId = genSessionId();
  const agentEntry = await spawnAgent({
    agentId: newAgentId,
    agentConfig,
    prompt: renderedPrompt,
    worktreePath: wt.path,
    tmuxTarget: windowTarget,
    projectRoot,
    branch: wt.branch,
    sessionId: newSessionId,
  });

  await updateManifest(projectRoot, (m) => {
    const mWt = m.worktrees[wt.id];
    if (mWt) {
      const mOldAgent = mWt.agents[oldAgent.id];
      if (mOldAgent && mOldAgent.status === 'running') {
        mOldAgent.status = 'gone';
      }
      mWt.agents[newAgentId] = agentEntry;
    }
    return m;
  });

  return {
    oldAgentId: oldAgent.id,
    newAgentId,
    tmuxTarget: windowTarget,
    sessionId: newSessionId,
    worktreeId: wt.id,
    worktreeName: wt.name,
    branch: wt.branch,
    path: wt.path,
  };
}

async function fileExists(filePath: string): Promise<boolean> {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}
