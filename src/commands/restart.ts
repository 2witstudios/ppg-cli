import fs from 'node:fs/promises';
import { requireManifest, findAgent } from '../core/manifest.js';
import { loadConfig, resolveAgentConfig } from '../core/config.js';
import { restartAgent } from '../core/agent.js';
import { getRepoRoot } from '../core/worktree.js';
import { openTerminalWindow } from '../core/terminal.js';
import { agentPromptFile } from '../lib/paths.js';
import { PpgError, AgentNotFoundError } from '../lib/errors.js';
import { output, success, info } from '../lib/output.js';

export interface RestartOptions {
  prompt?: string;
  agent?: string;
  open?: boolean;
  json?: boolean;
}

export async function restartCommand(agentRef: string, options: RestartOptions): Promise<void> {
  const projectRoot = await getRepoRoot();
  const config = await loadConfig(projectRoot);

  const manifest = await requireManifest(projectRoot);

  const found = findAgent(manifest, agentRef);
  if (!found) throw new AgentNotFoundError(agentRef);

  const { worktree: wt, agent: oldAgent } = found;

  // Read original prompt from prompt file, or use override
  let promptText: string;
  if (options.prompt) {
    promptText = options.prompt;
  } else {
    const pFile = agentPromptFile(projectRoot, oldAgent.id);
    try {
      promptText = await fs.readFile(pFile, 'utf-8');
    } catch {
      throw new PpgError(
        `Could not read original prompt for agent ${oldAgent.id}. Use --prompt to provide one.`,
        'PROMPT_NOT_FOUND',
      );
    }
  }

  const agentConfig = resolveAgentConfig(config, options.agent ?? oldAgent.agentType);

  if (oldAgent.status === 'running') {
    info(`Killing existing agent ${oldAgent.id}`);
  }

  const result = await restartAgent({
    projectRoot,
    agentId: oldAgent.id,
    worktree: wt,
    oldAgent,
    sessionName: manifest.sessionName,
    agentConfig,
    promptText,
  });

  // Only open Terminal window when explicitly requested via --open (fire-and-forget)
  if (options.open === true) {
    openTerminalWindow(manifest.sessionName, result.tmuxTarget, `${wt.name}-restart`).catch(() => {});
  }

  if (options.json) {
    output({
      success: true,
      oldAgentId: result.oldAgentId,
      newAgent: {
        id: result.newAgentId,
        tmuxTarget: result.tmuxTarget,
        sessionId: result.sessionId,
        worktreeId: result.worktreeId,
        worktreeName: result.worktreeName,
        branch: result.branch,
        path: result.path,
      },
    }, true);
  } else {
    success(`Restarted agent ${result.oldAgentId} → ${result.newAgentId} in worktree ${wt.name}`);
    info(`  New agent ${result.newAgentId} → ${result.tmuxTarget}`);
  }
}
