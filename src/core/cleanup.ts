import { updateManifest, readManifest, getWorktree } from './manifest.js';
import { removeWorktree } from './worktree.js';
import { teardownWorktreeEnv } from './env.js';
import * as tmux from './tmux.js';
import { warn } from '../lib/output.js';
import type { WorktreeEntry } from '../types/manifest.js';

/**
 * Clean up a worktree: kill tmux windows, teardown env, remove git worktree, update manifest.
 */
export async function cleanupWorktree(
  projectRoot: string,
  wt: WorktreeEntry,
): Promise<void> {
  // Kill tmux windows in parallel
  const windowKills: Promise<void>[] = [];
  for (const agent of Object.values(wt.agents)) {
    if (agent.tmuxTarget) {
      windowKills.push(tmux.killWindow(agent.tmuxTarget).catch(() => {}));
    }
  }
  if (wt.tmuxWindow) {
    windowKills.push(tmux.killWindow(wt.tmuxWindow).catch(() => {}));
  }
  await Promise.all(windowKills);

  // Teardown env
  try {
    await teardownWorktreeEnv(wt.path);
  } catch { /* may already be cleaned */ }

  // Remove git worktree + branch
  try {
    await removeWorktree(projectRoot, wt.path, {
      force: true,
      deleteBranch: true,
      branchName: wt.branch,
    });
  } catch (err) {
    warn(`Could not fully remove worktree ${wt.id}: ${err instanceof Error ? err.message : err}`);
  }

  // Update manifest
  await updateManifest(projectRoot, (m) => {
    if (m.worktrees[wt.id]) {
      m.worktrees[wt.id].status = 'cleaned';
    }
    return m;
  });
}
