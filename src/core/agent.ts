import fs from 'node:fs/promises';
import { resultFile, agentPromptFile, agentPromptsDir } from '../lib/paths.js';
import { getPaneInfo, listSessionPanes, type PaneInfo } from './tmux.js';
import { updateManifest } from './manifest.js';
import { PgError } from '../lib/errors.js';
import type { AgentEntry, AgentStatus } from '../types/manifest.js';
import type { AgentConfig } from '../types/config.js';
import { renderTemplate, type TemplateContext } from './template.js';
import * as tmux from './tmux.js';

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
  skipResultInstructions?: boolean;
}

export async function spawnAgent(options: SpawnAgentOptions): Promise<AgentEntry> {
  const {
    agentId,
    agentConfig,
    prompt,
    worktreePath,
    tmuxTarget,
    projectRoot,
    branch,
  } = options;

  const resFile = resultFile(projectRoot, agentId);

  // Build full prompt with result instructions
  let fullPrompt = prompt;
  if (agentConfig.resultInstructions && !options.skipResultInstructions) {
    const ctx: TemplateContext = {
      WORKTREE_PATH: worktreePath,
      BRANCH: branch,
      AGENT_ID: agentId,
      RESULT_FILE: resFile,
      PROJECT_ROOT: projectRoot,
    };
    const instructions = renderTemplate(agentConfig.resultInstructions, ctx);
    fullPrompt += `\n\n---\n\n${instructions}`;
  }

  // Write prompt to file
  const pFile = agentPromptFile(projectRoot, agentId);
  await fs.mkdir(agentPromptsDir(projectRoot), { recursive: true });
  await fs.writeFile(pFile, fullPrompt, 'utf-8');

  // Build and send command
  const command = buildAgentCommand(agentConfig, pFile, options.sessionId);
  await tmux.sendKeys(tmuxTarget, command);

  return {
    id: agentId,
    name: agentConfig.name,
    agentType: agentConfig.name,
    status: 'running',
    tmuxTarget,
    prompt: prompt.slice(0, 500), // Truncate for manifest storage
    resultFile: resFile,
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
 * Check agent status using the layered signal stack.
 * Checked in order of signal strength:
 * 1. Result file exists → completed
 * 2. Tmux pane doesn't exist → lost
 * 3. Pane is dead → completed/failed based on exit code
 * 4. Current command is a shell → agent exited → completed/failed
 * 5. Otherwise → running
 *
 * @param paneMap Optional pre-fetched pane map from listSessionPanes() for batch queries
 */
export async function checkAgentStatus(
  agent: AgentEntry,
  projectRoot: string,
  paneMap?: Map<string, PaneInfo>,
): Promise<{ status: AgentStatus; exitCode?: number }> {
  // If already in terminal state, don't re-check
  if (['completed', 'failed', 'killed', 'lost'].includes(agent.status)) {
    return { status: agent.status, exitCode: agent.exitCode };
  }

  // 1. Check result file
  const hasResult = await fileExists(agent.resultFile);
  if (hasResult) {
    return { status: 'completed' };
  }

  // 2. Check if tmux pane exists (use batch map if available)
  const paneInfo = paneMap
    ? (paneMap.get(agent.tmuxTarget) ?? null)
    : await getPaneInfo(agent.tmuxTarget);
  if (!paneInfo) {
    return { status: 'lost' };
  }

  // 3. Check if pane is dead
  if (paneInfo.isDead) {
    const exitCode = paneInfo.deadStatus;
    // Check result file one more time (may have been written right before exit)
    const hasResultNow = await fileExists(agent.resultFile);
    if (hasResultNow || exitCode === 0) {
      return { status: 'completed', exitCode: exitCode ?? 0 };
    }
    return { status: 'failed', exitCode };
  }

  // 4. Check if current command is a shell (agent process exited, returned to shell)
  if (SHELL_COMMANDS.has(paneInfo.currentCommand)) {
    // Agent process exited, back to shell prompt
    const hasResultNow = await fileExists(agent.resultFile);
    if (hasResultNow) {
      return { status: 'completed', exitCode: 0 };
    }
    return { status: 'failed', exitCode: undefined };
  }

  // 5. Still running
  return { status: 'running' };
}

export async function refreshAllAgentStatuses(
  manifest: import('../types/manifest.js').Manifest,
  projectRoot: string,
): Promise<import('../types/manifest.js').Manifest> {
  // Batch-fetch all pane info in a single tmux call
  const paneMap = await listSessionPanes(manifest.sessionName);

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
  const now = new Date().toISOString();
  for (let i = 0; i < checks.length; i++) {
    const { agent } = checks[i];
    const { status, exitCode } = results[i];
    if (status !== agent.status) {
      agent.status = status;
      if (exitCode !== undefined) agent.exitCode = exitCode;
      if (['completed', 'failed', 'lost'].includes(status) && !agent.completedAt) {
        agent.completedAt = now;
      }
    }
  }

  // Check worktree directories in parallel
  const wtChecks = Object.values(manifest.worktrees)
    .filter((wt) => wt.status === 'active')
    .map(async (wt) => {
      const exists = await fileExists(wt.path);
      if (!exists) {
        wt.status = 'cleaned';
        for (const agent of Object.values(wt.agents)) {
          if (!['completed', 'failed', 'killed'].includes(agent.status)) {
            agent.status = 'lost';
            if (!agent.completedAt) agent.completedAt = now;
          }
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
    throw new PgError(
      `Agent ${agent.id} has no session ID. Cannot resume agents spawned before session tracking was added.`,
      'NO_SESSION_ID',
    );
  }

  await tmux.ensureSession(sessionName);
  const newTarget = await tmux.createWindow(sessionName, windowName, cwd);
  await tmux.sendKeys(newTarget, `unset CLAUDECODE; claude --resume ${agent.sessionId}`);

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
  const initialInfo = await getPaneInfo(agent.tmuxTarget);
  if (!initialInfo || initialInfo.isDead) return;

  // Send Ctrl-C first (pane may die between check and send)
  try {
    await tmux.sendCtrlC(agent.tmuxTarget);
  } catch {
    // Pane died between check and send — already gone
    return;
  }

  // Wait for graceful shutdown (Claude Code needs more time)
  await new Promise((resolve) => setTimeout(resolve, 2000));

  // Check if still alive
  const paneInfo = await getPaneInfo(agent.tmuxTarget);
  if (paneInfo && !paneInfo.isDead) {
    // Kill the pane
    await tmux.killPane(agent.tmuxTarget);
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
    const info = await getPaneInfo(a.tmuxTarget);
    if (info && !info.isDead) alive.push(a);
  }));
  if (alive.length === 0) return;

  // Send Ctrl-C to all live agents in parallel (catch pane-died-between-check-and-send)
  await Promise.all(alive.map((a) => tmux.sendCtrlC(a.tmuxTarget).catch(() => {})));

  // Wait for graceful shutdown (Claude Code needs more time)
  await new Promise((resolve) => setTimeout(resolve, 2000));

  // Check and force-kill survivors in parallel
  await Promise.all(alive.map(async (a) => {
    const paneInfo = await getPaneInfo(a.tmuxTarget);
    if (paneInfo && !paneInfo.isDead) {
      await tmux.killPane(a.tmuxTarget);
    }
  }));
}

async function fileExists(filePath: string): Promise<boolean> {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}
