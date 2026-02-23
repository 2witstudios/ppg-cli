import { execa } from 'execa';
import { readManifest, findAgent } from '../core/manifest.js';
import { getRepoRoot } from '../core/worktree.js';
import * as tmux from '../core/tmux.js';
import { NotInitializedError, AgentNotFoundError } from '../lib/errors.js';
import { output, success } from '../lib/output.js';

export interface SendOptions {
  keys?: boolean;
  enter?: boolean;
  json?: boolean;
}

export async function sendCommand(agentId: string, text: string, options: SendOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  let manifest;
  try {
    manifest = await readManifest(projectRoot);
  } catch {
    throw new NotInitializedError(projectRoot);
  }

  const found = findAgent(manifest, agentId);
  if (!found) throw new AgentNotFoundError(agentId);

  const { agent } = found;

  if (options.keys) {
    // Raw tmux key names (e.g., "C-c", "Enter", "Escape")
    await execa('tmux', ['send-keys', '-t', agent.tmuxTarget, text]);
  } else if (options.enter === false) {
    // Send literal text without Enter
    await execa('tmux', ['send-keys', '-t', agent.tmuxTarget, '-l', text]);
  } else {
    // Default: send literal text + Enter
    await tmux.sendKeys(agent.tmuxTarget, text);
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
