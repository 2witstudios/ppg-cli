import { execa } from 'execa';
import { readManifest, updateManifest, getWorktree } from '../core/manifest.js';
import { refreshAllAgentStatuses } from '../core/agent.js';
import { getRepoRoot, removeWorktree } from '../core/worktree.js';
import { teardownWorktreeEnv } from '../core/env.js';
import * as tmux from '../core/tmux.js';
import { NotInitializedError, WorktreeNotFoundError } from '../lib/errors.js';
import { output, success, info, warn } from '../lib/output.js';

export interface MergeOptions {
  strategy?: 'squash' | 'no-ff';
  cleanup?: boolean;
  dryRun?: boolean;
  force?: boolean;
  json?: boolean;
}

export async function mergeCommand(worktreeId: string, options: MergeOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  let manifest;
  try {
    manifest = await updateManifest(projectRoot, async (m) => {
      return refreshAllAgentStatuses(m, projectRoot);
    });
  } catch {
    throw new NotInitializedError(projectRoot);
  }

  const wt = getWorktree(manifest, worktreeId)
    ?? Object.values(manifest.worktrees).find((w) => w.name === worktreeId);

  if (!wt) throw new WorktreeNotFoundError(worktreeId);

  // Check all agents completed
  const agents = Object.values(wt.agents);
  const incomplete = agents.filter((a) => !['completed', 'failed', 'killed'].includes(a.status));

  if (incomplete.length > 0 && !options.force) {
    const ids = incomplete.map((a) => a.id).join(', ');
    throw new Error(
      `${incomplete.length} agent(s) still running: ${ids}. Use --force to merge anyway.`,
    );
  }

  if (options.dryRun) {
    info('Dry run — no changes will be made');
    info(`Would merge branch ${wt.branch} into ${wt.baseBranch} using ${options.strategy ?? 'squash'} strategy`);
    if (options.cleanup !== false) {
      info(`Would remove worktree ${wt.id} and delete branch ${wt.branch}`);
    }
    return;
  }

  // Set worktree status to merging
  await updateManifest(projectRoot, (m) => {
    if (m.worktrees[wt.id]) {
      m.worktrees[wt.id].status = 'merging';
    }
    return m;
  });

  const strategy = options.strategy ?? 'squash';

  try {
    info(`Merging ${wt.branch} into ${wt.baseBranch} (${strategy})`);

    if (strategy === 'squash') {
      await execa('git', ['merge', '--squash', wt.branch], { cwd: projectRoot });
      await execa('git', ['commit', '-m', `pg: merge ${wt.name} (${wt.branch})`], {
        cwd: projectRoot,
      });
    } else {
      await execa('git', ['merge', '--no-ff', wt.branch, '-m', `pg: merge ${wt.name} (${wt.branch})`], {
        cwd: projectRoot,
      });
    }

    await updateManifest(projectRoot, (m) => {
      if (m.worktrees[wt.id]) {
        m.worktrees[wt.id].status = 'merged';
        m.worktrees[wt.id].mergedAt = new Date().toISOString();
      }
      return m;
    });

    success(`Merged ${wt.branch} into ${wt.baseBranch}`);
  } catch (err) {
    await updateManifest(projectRoot, (m) => {
      if (m.worktrees[wt.id]) {
        m.worktrees[wt.id].status = 'failed';
      }
      return m;
    });
    throw new Error(`Merge failed: ${err instanceof Error ? err.message : err}`);
  }

  // Cleanup
  if (options.cleanup !== false) {
    info('Cleaning up...');

    // Kill tmux window
    try {
      await tmux.killWindow(wt.tmuxWindow);
    } catch { /* already dead */ }

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
      warn(`Could not fully remove worktree: ${err instanceof Error ? err.message : err}`);
    }

    await updateManifest(projectRoot, (m) => {
      if (m.worktrees[wt.id]) {
        m.worktrees[wt.id].status = 'cleaned';
      }
      return m;
    });

    success(`Cleaned up worktree ${wt.id}`);
  }

  if (options.json) {
    output({
      success: true,
      worktreeId: wt.id,
      branch: wt.branch,
      baseBranch: wt.baseBranch,
      strategy,
      cleaned: options.cleanup !== false,
    }, true);
  }
}
