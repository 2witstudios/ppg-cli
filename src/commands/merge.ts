import { performMerge } from '../core/operations/merge.js';
import { getRepoRoot } from '../core/worktree.js';
import { output, success, info, warn } from '../lib/output.js';

export interface MergeCommandOptions {
  strategy?: 'squash' | 'no-ff';
  cleanup?: boolean;
  dryRun?: boolean;
  force?: boolean;
  json?: boolean;
}

export async function mergeCommand(worktreeId: string, options: MergeCommandOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  if (options.dryRun) {
    info('Dry run — no changes will be made');
  }

  const result = await performMerge({
    projectRoot,
    worktreeRef: worktreeId,
    strategy: options.strategy,
    cleanup: options.cleanup,
    dryRun: options.dryRun,
    force: options.force,
  });

  if (result.dryRun) {
    info(`Would merge branch ${result.branch} into ${result.baseBranch} using ${result.strategy} strategy`);
    if (options.cleanup !== false) {
      info(`Would remove worktree ${result.worktreeId} and delete branch ${result.branch}`);
    }
    return;
  }

  success(`Merged ${result.branch} into ${result.baseBranch}`);

  if (result.cleaned) {
    if (result.selfProtected) {
      warn('Some tmux targets skipped during cleanup — contains current ppg process');
    }
    success(`Cleaned up worktree ${result.worktreeId}`);
  }

  if (options.json) {
    output({
      success: true,
      worktreeId: result.worktreeId,
      branch: result.branch,
      baseBranch: result.baseBranch,
      strategy: result.strategy,
      cleaned: result.cleaned,
      selfProtected: result.selfProtected || undefined,
    }, true);
  }
}
