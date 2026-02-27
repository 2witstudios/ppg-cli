import { execa } from 'execa';
import { updateManifest } from './manifest.js';
import { getCurrentBranch } from './worktree.js';
import { cleanupWorktree, type CleanupOptions } from './cleanup.js';
import { PpgError, MergeFailedError } from '../lib/errors.js';
import { execaEnv } from '../lib/env.js';
import type { WorktreeEntry } from '../types/manifest.js';

export interface MergeWorktreeOptions {
  strategy?: 'squash' | 'no-ff';
  cleanup?: boolean;
  force?: boolean;
  cleanupOptions?: CleanupOptions;
}

export interface MergeWorktreeResult {
  worktreeId: string;
  branch: string;
  baseBranch: string;
  strategy: 'squash' | 'no-ff';
  cleaned: boolean;
  selfProtected: boolean;
}

/** Merge a worktree branch into its base branch. Updates manifest status throughout. */
export async function mergeWorktree(
  projectRoot: string,
  wt: WorktreeEntry,
  options: MergeWorktreeOptions = {},
): Promise<MergeWorktreeResult> {
  const { strategy = 'squash', cleanup = true, force = false } = options;

  // Check all agents finished
  const incomplete = Object.values(wt.agents).filter((a) => a.status === 'running');
  if (incomplete.length > 0 && !force) {
    const ids = incomplete.map((a) => a.id).join(', ');
    throw new PpgError(
      `${incomplete.length} agent(s) still running: ${ids}. Use --force to merge anyway.`,
      'AGENTS_RUNNING',
    );
  }

  // Set worktree status to merging
  await updateManifest(projectRoot, (m) => {
    if (m.worktrees[wt.id]) {
      m.worktrees[wt.id].status = 'merging';
    }
    return m;
  });

  try {
    const currentBranch = await getCurrentBranch(projectRoot);
    if (currentBranch !== wt.baseBranch) {
      await execa('git', ['checkout', wt.baseBranch], { ...execaEnv, cwd: projectRoot });
    }

    if (strategy === 'squash') {
      await execa('git', ['merge', '--squash', wt.branch], { ...execaEnv, cwd: projectRoot });
      await execa('git', ['commit', '-m', `ppg: merge ${wt.name} (${wt.branch})`], {
        ...execaEnv,
        cwd: projectRoot,
      });
    } else {
      await execa('git', ['merge', '--no-ff', wt.branch, '-m', `ppg: merge ${wt.name} (${wt.branch})`], {
        ...execaEnv,
        cwd: projectRoot,
      });
    }
  } catch (err) {
    await updateManifest(projectRoot, (m) => {
      if (m.worktrees[wt.id]) {
        m.worktrees[wt.id].status = 'failed';
      }
      return m;
    });
    throw new MergeFailedError(
      `Merge failed: ${err instanceof Error ? err.message : err}`,
    );
  }

  // Mark as merged
  await updateManifest(projectRoot, (m) => {
    if (m.worktrees[wt.id]) {
      m.worktrees[wt.id].status = 'merged';
      m.worktrees[wt.id].mergedAt = new Date().toISOString();
    }
    return m;
  });

  // Cleanup
  let selfProtected = false;
  if (cleanup) {
    const cleanupResult = await cleanupWorktree(projectRoot, wt, options.cleanupOptions);
    selfProtected = cleanupResult.selfProtected;
  }

  return {
    worktreeId: wt.id,
    branch: wt.branch,
    baseBranch: wt.baseBranch,
    strategy,
    cleaned: cleanup,
    selfProtected,
  };
}
