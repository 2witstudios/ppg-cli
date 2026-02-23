import { readManifest, getWorktree, findAgent } from '../core/manifest.js';
import { getRepoRoot } from '../core/worktree.js';
import * as tmux from '../core/tmux.js';
import { NotInitializedError } from '../lib/errors.js';
import { info } from '../lib/output.js';

export async function attachCommand(target: string): Promise<void> {
  const projectRoot = await getRepoRoot();

  let manifest;
  try {
    manifest = await readManifest(projectRoot);
  } catch {
    throw new NotInitializedError(projectRoot);
  }

  // Try to resolve target as worktree ID, worktree name, or agent ID
  let tmuxTarget: string | undefined;
  let sessionName = manifest.sessionName;

  // Check worktree ID
  const wt = getWorktree(manifest, target)
    ?? Object.values(manifest.worktrees).find((w) => w.name === target);

  if (wt) {
    tmuxTarget = wt.tmuxWindow;
  } else {
    // Check agent ID
    const found = findAgent(manifest, target);
    if (found) {
      tmuxTarget = found.agent.tmuxTarget;
    }
  }

  if (!tmuxTarget) {
    throw new Error(`Could not resolve target: ${target}. Try a worktree ID, name, or agent ID.`);
  }

  const insideTmux = await tmux.isInsideTmux();

  if (insideTmux) {
    // Switch to the window/pane within current tmux session
    if (wt) {
      await tmux.selectWindow(tmuxTarget);
    } else {
      await tmux.selectPane(tmuxTarget);
    }
    info(`Switched to ${tmuxTarget}`);
  } else {
    // Attach to the tmux session, then select the target
    info(`Attaching to session ${sessionName}, target ${tmuxTarget}`);
    if (wt) {
      await tmux.selectWindow(tmuxTarget);
    }
    await tmux.attachSession(sessionName);
  }
}
