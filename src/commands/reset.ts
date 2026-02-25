import { updateManifest } from '../core/manifest.js';
import { refreshAllAgentStatuses, killAgents } from '../core/agent.js';
import { getRepoRoot, pruneWorktrees } from '../core/worktree.js';
import { cleanupWorktree } from '../core/cleanup.js';
import { getCurrentPaneId, excludeSelf, wouldCleanupAffectSelf } from '../core/self.js';
import { listSessionPanes, type PaneInfo } from '../core/tmux.js';
import { NotInitializedError, UnmergedWorkError } from '../lib/errors.js';
import { output, success, info, warn } from '../lib/output.js';
import type { AgentEntry, WorktreeEntry } from '../types/manifest.js';

/** Identify worktrees with completed agents that haven't been merged or PR'd. */
export function findAtRiskWorktrees(worktrees: WorktreeEntry[]): WorktreeEntry[] {
  return worktrees.filter((wt) => {
    if (wt.status === 'merged' || wt.status === 'cleaned') return false;
    if (wt.prUrl) return false;
    return Object.values(wt.agents).some((a) => a.status === 'completed');
  });
}

export interface ResetOptions {
  force?: boolean;
  prune?: boolean;
  json?: boolean;
}

export async function resetCommand(options: ResetOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  let manifest;
  try {
    manifest = await updateManifest(projectRoot, async (m) => {
      return refreshAllAgentStatuses(m, projectRoot);
    });
  } catch {
    throw new NotInitializedError(projectRoot);
  }

  const worktrees = Object.values(manifest.worktrees);

  if (worktrees.length === 0) {
    if (options.json) {
      output({ success: true, killed: [], removed: [], warned: [] }, true);
    } else {
      info('Nothing to reset — no worktrees in manifest');
    }
    return;
  }

  // Safety check: identify worktrees with unmerged/un-PR'd completed work
  const atRisk = findAtRiskWorktrees(worktrees);

  if (atRisk.length > 0 && !options.force) {
    throw new UnmergedWorkError(atRisk.map((wt) => `${wt.name} (${wt.branch})`));
  }

  if (atRisk.length > 0) {
    warn(`${atRisk.length} worktree(s) have unmerged/un-PR'd work — proceeding with --force`);
  }

  // Build self-protection context
  const selfPaneId = getCurrentPaneId();
  let paneMap: Map<string, PaneInfo> | undefined;
  if (selfPaneId) {
    paneMap = await listSessionPanes(manifest.sessionName);
  }

  // Collect all running agents
  const allAgents: AgentEntry[] = [];
  for (const wt of worktrees) {
    for (const agent of Object.values(wt.agents)) {
      if (['running', 'spawning', 'waiting'].includes(agent.status)) {
        allAgents.push(agent);
      }
    }
  }

  // Self-protection for agents
  let agentsToKill = allAgents;
  const skippedAgentIds: string[] = [];
  if (selfPaneId && paneMap) {
    const { safe, skipped } = excludeSelf(allAgents, selfPaneId, paneMap);
    agentsToKill = safe;
    for (const a of skipped) {
      skippedAgentIds.push(a.id);
      warn(`Skipping agent ${a.id} — contains current ppg process`);
    }
  }

  // Kill running agents
  const killedIds = agentsToKill.map((a) => a.id);
  if (agentsToKill.length > 0) {
    info(`Killing ${agentsToKill.length} running agent(s)`);
    await killAgents(agentsToKill);
  }

  // Update agent statuses in manifest
  if (killedIds.length > 0) {
    await updateManifest(projectRoot, (m) => {
      const now = new Date().toISOString();
      for (const wt of Object.values(m.worktrees)) {
        for (const agent of Object.values(wt.agents)) {
          if (killedIds.includes(agent.id)) {
            agent.status = 'killed';
            agent.completedAt = now;
          }
        }
      }
      return m;
    });
  }

  // Cleanup all worktrees (skip already cleaned/merged that are already gone)
  const removedIds: string[] = [];
  const skippedWorktreeIds: string[] = [];

  for (const wt of worktrees) {
    // Self-protection check for worktree cleanup
    if (selfPaneId && paneMap && wouldCleanupAffectSelf(wt, selfPaneId, paneMap)) {
      warn(`Skipping cleanup of worktree ${wt.id} (${wt.name}) — contains current ppg process`);
      skippedWorktreeIds.push(wt.id);
      continue;
    }

    if (wt.status !== 'cleaned') {
      info(`Removing worktree ${wt.id} (${wt.name})`);
      await cleanupWorktree(projectRoot, wt, { selfPaneId, paneMap });
    }
    removedIds.push(wt.id);
  }

  // Remove all cleaned worktrees from manifest
  if (removedIds.length > 0) {
    await updateManifest(projectRoot, (m) => {
      for (const id of removedIds) {
        delete m.worktrees[id];
      }
      return m;
    });
  }

  // Optional git worktree prune
  if (options.prune) {
    info('Pruning stale git worktrees');
    await pruneWorktrees(projectRoot);
  }

  const warnedNames = atRisk.map((wt) => wt.name);

  if (options.json) {
    output({
      success: true,
      killed: killedIds,
      removed: removedIds,
      warned: warnedNames.length > 0 ? warnedNames : undefined,
      skipped: skippedWorktreeIds.length > 0 ? skippedWorktreeIds : undefined,
      pruned: options.prune ?? false,
    }, true);
  } else {
    if (killedIds.length > 0) {
      success(`Killed ${killedIds.length} agent(s)`);
    }
    if (removedIds.length > 0) {
      success(`Removed ${removedIds.length} worktree(s)`);
    }
    if (skippedWorktreeIds.length > 0) {
      warn(`Skipped ${skippedWorktreeIds.length} worktree(s) due to self-protection`);
    }
    if (options.prune) {
      success('Pruned stale git worktrees');
    }
    if (killedIds.length > 0 || removedIds.length > 0) {
      success('Reset complete');
    } else {
      info('Nothing to reset');
    }
  }
}
