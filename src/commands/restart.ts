import { performRestart } from '../core/operations/restart.js';
import { openTerminalWindow } from '../core/terminal.js';
import { output, success, info } from '../lib/output.js';

export interface RestartOptions {
  prompt?: string;
  agent?: string;
  open?: boolean;
  json?: boolean;
}

export async function restartCommand(agentRef: string, options: RestartOptions): Promise<void> {
  const result = await performRestart({
    agentRef,
    prompt: options.prompt,
    agentType: options.agent,
  });

  // Only open Terminal window when explicitly requested via --open (fire-and-forget)
  if (options.open === true) {
    openTerminalWindow(result.sessionName, result.newAgent.tmuxTarget, `${result.newAgent.worktreeName}-restart`).catch(() => {});
  }

  if (options.json) {
    output({
      success: true,
      oldAgentId: result.oldAgentId,
      newAgent: result.newAgent,
    }, true);
  } else {
    if (result.killedOldAgent) {
      info(`Killed existing agent ${result.oldAgentId}`);
    }
    success(`Restarted agent ${result.oldAgentId} → ${result.newAgent.id} in worktree ${result.newAgent.worktreeName}`);
    info(`  New agent ${result.newAgent.id} → ${result.newAgent.tmuxTarget}`);
  }
}
