import fs from 'node:fs/promises';
import { resultFile, promptFile } from '../lib/paths.js';
import { getPaneInfo } from './tmux.js';
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
  if (agentConfig.resultInstructions) {
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
  const pFile = promptFile(projectRoot, agentId);
  await fs.writeFile(pFile, fullPrompt, 'utf-8');

  // Build and send command
  const command = buildAgentCommand(agentConfig, pFile);
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
  };
}

function buildAgentCommand(agentConfig: AgentConfig, promptFilePath: string): string {
  // Unset CLAUDECODE so spawned Claude instances don't think they're nested
  const envPrefix = 'unset CLAUDECODE;';
  const { command, promptFlag } = agentConfig;
  if (promptFlag) {
    // Use explicit flag: command --flag "$(cat prompt-file)"
    return `${envPrefix} ${command} ${promptFlag} "$(cat ${promptFilePath})"`;
  }
  // Pass prompt as positional argument: command "$(cat prompt-file)"
  return `${envPrefix} ${command} "$(cat ${promptFilePath})"`;
}

/**
 * Check agent status using the layered signal stack.
 * Checked in order of signal strength:
 * 1. Result file exists → completed
 * 2. Tmux pane doesn't exist → lost
 * 3. Pane is dead → completed/failed based on exit code
 * 4. Current command is a shell → agent exited → completed/failed
 * 5. Otherwise → running
 */
export async function checkAgentStatus(
  agent: AgentEntry,
  projectRoot: string,
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

  // 2. Check if tmux pane exists
  const paneInfo = await getPaneInfo(agent.tmuxTarget);
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
  for (const wt of Object.values(manifest.worktrees)) {
    for (const agent of Object.values(wt.agents)) {
      const { status, exitCode } = await checkAgentStatus(agent, projectRoot);
      if (status !== agent.status) {
        agent.status = status;
        if (exitCode !== undefined) agent.exitCode = exitCode;
        if (['completed', 'failed', 'lost'].includes(status) && !agent.completedAt) {
          agent.completedAt = new Date().toISOString();
        }
      }
    }

    // Check if worktree directory still exists
    if (wt.status === 'active') {
      const exists = await fileExists(wt.path);
      if (!exists) {
        wt.status = 'cleaned';
        for (const agent of Object.values(wt.agents)) {
          if (!['completed', 'failed', 'killed'].includes(agent.status)) {
            agent.status = 'lost';
            if (!agent.completedAt) agent.completedAt = new Date().toISOString();
          }
        }
      }
    }
  }
  return manifest;
}

export async function killAgent(agent: AgentEntry): Promise<void> {
  // Send Ctrl-C first
  await tmux.sendCtrlC(agent.tmuxTarget);

  // Wait a moment
  await new Promise((resolve) => setTimeout(resolve, 2000));

  // Check if still alive
  const paneInfo = await getPaneInfo(agent.tmuxTarget);
  if (paneInfo && !paneInfo.isDead) {
    // Kill the pane
    await tmux.killPane(agent.tmuxTarget);
  }
}

async function fileExists(filePath: string): Promise<boolean> {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}
