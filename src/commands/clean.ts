import { readManifest, updateManifest } from '../core/manifest.js';
import { getRepoRoot, pruneWorktrees } from '../core/worktree.js';
import { cleanupWorktree } from '../core/cleanup.js';
import { getCurrentPaneId, wouldCleanupAffectSelf } from '../core/self.js';
import { listSessionPanes, type PaneInfo } from '../core/tmux.js';
import { NotInitializedError } from '../lib/errors.js';
import { output, success, info, warn } from '../lib/output.js';
import type { WorktreeEntry } from '../types/manifest.js';

export interface CleanOptions {
  all?: boolean;
  dryRun?: boolean;
  prune?: boolean;
  json?: boolean;
}

export async function cleanCommand(options: CleanOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  let manifest;
  try {
    manifest = await readManifest(projectRoot);
  } catch {
    throw new NotInitializedError(projectRoot);
  }

  // Build self-protection context if inside tmux
  const selfPaneId = getCurrentPaneId();
  let paneMap: Map<string, PaneInfo> | undefined;
  if (selfPaneId) {
    paneMap = await listSessionPanes(manifest.sessionName);
  }

  // Find worktrees in terminal states
  const terminalStatuses = ['merged', 'cleaned'];
  if (options.all) {
    terminalStatuses.push('failed');
  }

  const toClean = Object.values(manifest.worktrees)
    .filter((wt) => terminalStatuses.includes(wt.status));

  // Also find worktrees already marked 'cleaned' that still have manifest entries
  const toRemoveFromManifest = Object.values(manifest.worktrees)
    .filter((wt) => wt.status === 'cleaned');

  if (options.dryRun) {
    if (toClean.length === 0 && toRemoveFromManifest.length === 0) {
      info('Nothing to clean');
    } else {
      info('Dry run — would clean:');
      for (const wt of toClean) {
        if (wt.status !== 'cleaned') {
          info(`  ${wt.id} (${wt.name}) — ${wt.status}`);
        }
      }
      for (const wt of toRemoveFromManifest) {
        info(`  ${wt.id} (${wt.name}) — remove from manifest`);
      }
    }

    if (options.json) {
      output({
        dryRun: true,
        wouldClean: toClean.filter((wt) => wt.status !== 'cleaned').map((wt) => ({
          id: wt.id,
          name: wt.name,
          status: wt.status,
        })),
        wouldRemoveFromManifest: toRemoveFromManifest.map((wt) => ({
          id: wt.id,
          name: wt.name,
        })),
      }, true);
    }
    return;
  }

  // Clean worktrees that need cleanup (merged, failed but not yet cleaned)
  const cleaned: string[] = [];
  const skipped: string[] = [];
  const removed: string[] = [];

  for (const wt of toClean) {
    if (wt.status !== 'cleaned') {
      // Self-protection check before cleanup
      if (selfPaneId && paneMap && wouldCleanupAffectSelf(wt, selfPaneId, paneMap)) {
        warn(`Skipping cleanup of worktree ${wt.id} (${wt.name}) — contains current ppg process`);
        skipped.push(wt.id);
        continue;
      }

      info(`Cleaning worktree ${wt.id} (${wt.name})`);
      await cleanupWorktree(projectRoot, wt, { selfPaneId, paneMap });
      cleaned.push(wt.id);
    }
  }

  // Remove cleaned entries from manifest
  const allCleanedIds = [...new Set([
    ...toRemoveFromManifest.map((wt) => wt.id),
    ...cleaned,
  ])];

  if (allCleanedIds.length > 0) {
    await updateManifest(projectRoot, (m) => {
      for (const id of allCleanedIds) {
        delete m.worktrees[id];
      }
      return m;
    });
    removed.push(...allCleanedIds);
  }

  // Git worktree prune
  if (options.prune) {
    info('Pruning stale git worktrees');
    await pruneWorktrees(projectRoot);
  }

  if (options.json) {
    output({
      success: true,
      cleaned,
      skipped: skipped.length > 0 ? skipped : undefined,
      removedFromManifest: removed,
      pruned: options.prune ?? false,
    }, true);
  } else {
    if (cleaned.length > 0) {
      success(`Cleaned ${cleaned.length} worktree(s)`);
    }
    if (skipped.length > 0) {
      warn(`Skipped ${skipped.length} worktree(s) due to self-protection`);
    }
    if (removed.length > 0) {
      success(`Removed ${removed.length} worktree(s) from manifest`);
    }
    if (cleaned.length === 0 && removed.length === 0 && skipped.length === 0) {
      info('Nothing to clean');
    }
    if (options.prune) {
      success('Pruned stale git worktrees');
    }
  }
}
