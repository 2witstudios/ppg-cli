import { execa } from 'execa';
import { requireManifest, updateManifest, resolveWorktree } from '../manifest.js';
import { refreshAllAgentStatuses } from '../agent.js';
import { getCurrentBranch } from '../worktree.js';
import { cleanupWorktree } from '../cleanup.js';
import { getCurrentPaneId } from '../self.js';
import { listSessionPanes, type PaneInfo } from '../tmux.js';
import { PpgError, WorktreeNotFoundError, MergeFailedError } from '../../lib/errors.js';
import { execaEnv } from '../../lib/env.js';

export type MergeStrategy = 'squash' | 'no-ff';

export interface MergeOptions {
  projectRoot: string;
  worktreeRef: string;
  strategy?: MergeStrategy;
  cleanup?: boolean;
  dryRun?: boolean;
  force?: boolean;
}

export interface MergeResult {
  worktreeId: string;
  branch: string;
  baseBranch: string;
  strategy: MergeStrategy;
  dryRun: boolean;
  merged: boolean;
  cleaned: boolean;
  selfProtected: boolean;
}

/**
 * Perform a merge operation: resolve worktree, validate agents, run git merge,
 * and optionally clean up.
 *
 * State machine: active → merging → merged → cleaned
 * On failure:    active → merging → failed
 */
export async function performMerge(options: MergeOptions): Promise<MergeResult> {
  const { projectRoot, worktreeRef, force = false, dryRun = false } = options;
  const strategy = options.strategy ?? 'squash';
  const shouldCleanup = options.cleanup !== false;

  // Load and refresh manifest
  await requireManifest(projectRoot);
  const manifest = await updateManifest(projectRoot, async (m) => {
    return refreshAllAgentStatuses(m, projectRoot);
  });

  const wt = resolveWorktree(manifest, worktreeRef);
  if (!wt) throw new WorktreeNotFoundError(worktreeRef);

  // Validate: no running agents unless forced
  const agents = Object.values(wt.agents);
  const incomplete = agents.filter((a) => a.status === 'running');

  if (incomplete.length > 0 && !force) {
    const ids = incomplete.map((a) => a.id).join(', ');
    throw new PpgError(
      `${incomplete.length} agent(s) still running: ${ids}. Use --force to merge anyway.`,
      'AGENTS_RUNNING',
    );
  }

  // Dry run: return early without changes
  if (dryRun) {
    return {
      worktreeId: wt.id,
      branch: wt.branch,
      baseBranch: wt.baseBranch,
      strategy,
      dryRun: true,
      merged: false,
      cleaned: false,
      selfProtected: false,
    };
  }

  // Transition: active → merging
  await updateManifest(projectRoot, (m) => {
    if (m.worktrees[wt.id]) {
      m.worktrees[wt.id].status = 'merging';
    }
    return m;
  });

  // Perform git merge
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
    // Transition: merging → failed
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

  // Transition: merging → merged
  await updateManifest(projectRoot, (m) => {
    if (m.worktrees[wt.id]) {
      m.worktrees[wt.id].status = 'merged';
      m.worktrees[wt.id].mergedAt = new Date().toISOString();
    }
    return m;
  });

  // Cleanup (merged → cleaned)
  let selfProtected = false;
  if (shouldCleanup) {
    const selfPaneId = getCurrentPaneId();
    let paneMap: Map<string, PaneInfo> | undefined;
    if (selfPaneId) {
      paneMap = await listSessionPanes(manifest.sessionName);
    }

    const cleanupResult = await cleanupWorktree(projectRoot, wt, { selfPaneId, paneMap });
    selfProtected = cleanupResult.selfProtected;
  }

  return {
    worktreeId: wt.id,
    branch: wt.branch,
    baseBranch: wt.baseBranch,
    strategy,
    dryRun: false,
    merged: true,
    cleaned: shouldCleanup,
    selfProtected,
  };
}
