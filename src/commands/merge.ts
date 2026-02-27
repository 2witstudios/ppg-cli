import { requireManifest, updateManifest, resolveWorktree } from '../core/manifest.js';
import { refreshAllAgentStatuses } from '../core/agent.js';
import { getRepoRoot } from '../core/worktree.js';
import { mergeWorktree } from '../core/merge.js';
import { getCurrentPaneId } from '../core/self.js';
import { listSessionPanes } from '../core/tmux.js';
import { WorktreeNotFoundError } from '../lib/errors.js';
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

  await requireManifest(projectRoot);
  const manifest = await updateManifest(projectRoot, async (m) => {
    return refreshAllAgentStatuses(m, projectRoot);
  });

  const wt = resolveWorktree(manifest, worktreeId);

  if (!wt) throw new WorktreeNotFoundError(worktreeId);

  if (options.dryRun) {
    info('Dry run — no changes will be made');
    info(`Would merge branch ${wt.branch} into ${wt.baseBranch} using ${options.strategy ?? 'squash'} strategy`);
    if (options.cleanup !== false) {
      info(`Would remove worktree ${wt.id} and delete branch ${wt.branch}`);
    }
    return;
  }

  // Build self-protection context for cleanup
  const selfPaneId = getCurrentPaneId();
  let paneMap;
  if (selfPaneId) {
    paneMap = await listSessionPanes(manifest.sessionName);
  }

  info(`Merging ${wt.branch} into ${wt.baseBranch} (${options.strategy ?? 'squash'})`);

  const result = await mergeWorktree(projectRoot, wt, {
    strategy: options.strategy,
    cleanup: options.cleanup !== false,
    force: options.force,
    cleanupOptions: { selfPaneId, paneMap },
  });

  success(`Merged ${wt.branch} into ${wt.baseBranch}`);

  if (result.selfProtected) {
    warn(`Some tmux targets skipped during cleanup — contains current ppg process`);
  }
  if (result.cleaned) {
    success(`Cleaned up worktree ${wt.id}`);
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
