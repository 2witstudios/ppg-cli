import { requireManifest, findAgent } from '../core/manifest.js';
import { getRepoRoot } from '../core/worktree.js';
import { getBackend } from '../core/backend.js';
import { AgentNotFoundError } from '../lib/errors.js';
import { output, success } from '../lib/output.js';

export interface SendOptions {
  keys?: boolean;
  enter?: boolean;
  json?: boolean;
}

export async function sendCommand(agentId: string, text: string, options: SendOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  const manifest = await requireManifest(projectRoot);

  const found = findAgent(manifest, agentId);
  if (!found) throw new AgentNotFoundError(agentId);

  const { agent } = found;

  if (options.keys) {
    // Raw tmux key names (e.g., "C-c", "Enter", "Escape")
    await getBackend().sendRawKeys(agent.tmuxTarget, text);
  } else if (options.enter === false) {
    // Send literal text without Enter
    await getBackend().sendLiteral(agent.tmuxTarget, text);
  } else {
    // Default: send literal text + Enter
    await getBackend().sendKeys(agent.tmuxTarget, text);
  }

  if (options.json) {
    output({
      success: true,
      agentId: agent.id,
      tmuxTarget: agent.tmuxTarget,
      text,
    }, true);
  } else {
    success(`Sent to agent ${agent.id}`);
  }
}
