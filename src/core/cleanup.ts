import fs from 'node:fs/promises';
import { updateManifest } from './manifest.js';
import { removeWorktree } from './worktree.js';
import { teardownWorktreeEnv } from './env.js';
import { getBackend } from './backend.js';
import { agentPromptFile } from '../lib/paths.js';
import { warn } from '../lib/output.js';
import { wouldAffectSelf } from './self.js';
import type { PaneInfo } from './process-manager.js';
import type { WorktreeEntry } from '../types/manifest.js';

export interface CleanupOptions {
  /** Current process's tmux pane ID (from $TMUX_PANE). Null = not inside tmux. */
  selfPaneId?: string | null;
  /** Pre-fetched pane map from listSessionPanes(). */
  paneMap?: Map<string, PaneInfo>;
}

export interface CleanupResult {
  /** Worktree ID that was cleaned. */
  worktreeId: string;
  /** Whether manifest was updated to 'cleaned'. */
  manifestUpdated: boolean;
  /** Number of tmux windows successfully killed. */
  tmuxKilled: number;
  /** Number of tmux windows skipped (already gone). */
  tmuxSkipped: number;
  /** Number of tmux windows that failed to kill (unexpected error). */
  tmuxFailed: number;
  /** Whether any target was skipped due to self-protection. */
  selfProtected: boolean;
  /** Targets that were self-protected. */
  selfProtectedTargets: string[];
}

/**
 * Clean up a worktree: update manifest FIRST (crash-safe), then kill tmux, teardown env, remove git worktree.
 *
 * Operation order is designed so that if the process dies mid-cleanup,
 * the manifest already reflects the cleaned state.
 *
 * Idempotent: if worktree is already 'cleaned' in manifest, only attempts filesystem cleanup.
 */
export async function cleanupWorktree(
  projectRoot: string,
  wt: WorktreeEntry,
  options?: CleanupOptions,
): Promise<CleanupResult> {
  const selfPaneId = options?.selfPaneId ?? null;
  const paneMap = options?.paneMap ?? new Map<string, PaneInfo>();

  const result: CleanupResult = {
    worktreeId: wt.id,
    manifestUpdated: false,
    tmuxKilled: 0,
    tmuxSkipped: 0,
    tmuxFailed: 0,
    selfProtected: false,
    selfProtectedTargets: [],
  };

  const alreadyCleaned = wt.status === 'cleaned';

  // 1. Update manifest FIRST — crash-safe point
  if (!alreadyCleaned) {
    await updateManifest(projectRoot, (m) => {
      if (m.worktrees[wt.id]) {
        m.worktrees[wt.id].status = 'cleaned';
      }
      return m;
    });
    result.manifestUpdated = true;
  }

  // 2. Kill tmux windows — skip if already cleaned (tmux already gone),
  //    skip targets that match selfPaneId
  if (!alreadyCleaned) {
    const targets = new Set<string>();

    for (const agent of Object.values(wt.agents)) {
      if (agent.tmuxTarget) targets.add(agent.tmuxTarget);
    }
    if (wt.tmuxWindow) targets.add(wt.tmuxWindow);

    for (const target of targets) {
      // Self-protection check
      if (selfPaneId && wouldAffectSelf(target, selfPaneId, paneMap)) {
        result.selfProtected = true;
        result.selfProtectedTargets.push(target);
        warn(`Skipping tmux kill for ${target} — contains current process`);
        continue;
      }

      try {
        await getBackend().killWindow(target);
        result.tmuxKilled++;
      } catch (err) {
        // killWindow now only throws on unexpected errors (not "not found")
        result.tmuxFailed++;
        warn(`Failed to kill tmux window ${target}: ${err instanceof Error ? err.message : err}`);
      }
    }
  }

  // 3. Remove agent prompt files
  for (const agent of Object.values(wt.agents)) {
    const pFile = agentPromptFile(projectRoot, agent.id);
    await fs.rm(pFile, { force: true });
  }

  // 4. Teardown env
  try {
    await teardownWorktreeEnv(wt.path);
  } catch { /* may already be cleaned */ }

  // 5. Remove git worktree + branch
  try {
    await removeWorktree(projectRoot, wt.path, {
      force: true,
      deleteBranch: true,
      branchName: wt.branch,
    });
  } catch (err) {
    warn(`Could not fully remove worktree ${wt.id}: ${err instanceof Error ? err.message : err}`);
  }

  return result;
}
