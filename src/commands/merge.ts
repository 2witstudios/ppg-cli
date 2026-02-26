import { execa } from 'execa';
import { requireManifest, updateManifest, resolveWorktree } from '../core/manifest.js';
import { refreshAllAgentStatuses } from '../core/agent.js';
import { getRepoRoot, getCurrentBranch } from '../core/worktree.js';
import { cleanupWorktree } from '../core/cleanup.js';
import { getCurrentPaneId } from '../core/self.js';
import { listSessionPanes, type PaneInfo } from '../core/tmux.js';
import { PpgError, WorktreeNotFoundError, MergeFailedError } from '../lib/errors.js';
import { output, success, info, warn } from '../lib/output.js';
import { execaEnv } from '../lib/env.js';

export interface MergeOptions {
  strategy?: 'squash' | 'no-ff';
  cleanup?: boolean;
  dryRun?: boolean;
  force?: boolean;
  json?: boolean;
}

export async function mergeCommand(worktreeId: string, options: MergeOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  await requireManifest(projectRoot);
  const manifest = await updateManifest(projectRoot, async (m) => {
    return refreshAllAgentStatuses(m, projectRoot);
  });

  const wt = resolveWorktree(manifest, worktreeId);

  if (!wt) throw new WorktreeNotFoundError(worktreeId);

  // Check all agents completed
  const agents = Object.values(wt.agents);
  const incomplete = agents.filter((a) => !['completed', 'failed', 'killed'].includes(a.status));

  if (incomplete.length > 0 && !options.force) {
    const ids = incomplete.map((a) => a.id).join(', ');
    throw new PpgError(
      `${incomplete.length} agent(s) still running: ${ids}. Use --force to merge anyway.`,
      'AGENTS_RUNNING',
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
    const currentBranch = await getCurrentBranch(projectRoot);
    if (currentBranch !== wt.baseBranch) {
      info(`Switching to base branch ${wt.baseBranch}`);
      await execa('git', ['checkout', wt.baseBranch], { ...execaEnv, cwd: projectRoot });
    }

    info(`Merging ${wt.branch} into ${wt.baseBranch} (${strategy})`);

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

    success(`Merged ${wt.branch} into ${wt.baseBranch}`);
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

  // Cleanup with self-protection
  let selfProtected = false;
  if (options.cleanup !== false) {
    info('Cleaning up...');

    const selfPaneId = getCurrentPaneId();
    let paneMap: Map<string, PaneInfo> | undefined;
    if (selfPaneId) {
      paneMap = await listSessionPanes(manifest.sessionName);
    }

    const cleanupResult = await cleanupWorktree(projectRoot, wt, { selfPaneId, paneMap });
    selfProtected = cleanupResult.selfProtected;

    if (selfProtected) {
      warn(`Some tmux targets skipped during cleanup — contains current ppg process`);
    }
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
      selfProtected: selfProtected || undefined,
    }, true);
  }
}
