import type { PaneInfo } from './tmux.js';
import type { AgentEntry, WorktreeEntry } from '../types/manifest.js';

/**
 * Read the current process's tmux pane ID from the environment.
 * Returns null when not running inside tmux.
 */
export function getCurrentPaneId(): string | null {
  return process.env.TMUX_PANE ?? null;
}

/**
 * Check if a tmux target (pane ID, session:window, or session:window.pane)
 * would affect the pane the current process is running in.
 *
 * Uses the paneMap from listSessionPanes() which indexes by multiple formats.
 */
export function wouldAffectSelf(
  target: string,
  selfPaneId: string,
  paneMap: Map<string, PaneInfo>,
): boolean {
  // Direct match: target IS the self pane
  if (target === selfPaneId) return true;

  // Look up the target in the pane map
  const targetInfo = paneMap.get(target);
  if (!targetInfo) return false;

  // If target resolves to a specific pane, check if it's self
  if (targetInfo.paneId === selfPaneId) return true;

  // If target is a window (session:window format, no dot), check all panes in that window
  // The pane map indexes by session:window too, which maps to the first pane.
  // But a window kill would kill ALL panes in it, so we need to check if any pane
  // in that window is self.
  if (!target.includes('.') && target.includes(':')) {
    // This is a window-level target. Scan the map for all panes in this window.
    for (const [key, info] of paneMap) {
      if (key.startsWith(target + '.') && info.paneId === selfPaneId) {
        return true;
      }
    }
  }

  return false;
}

/**
 * Split an agent list into safe-to-kill and must-skip sets.
 */
export function excludeSelf(
  agents: AgentEntry[],
  selfPaneId: string,
  paneMap: Map<string, PaneInfo>,
): { safe: AgentEntry[]; skipped: AgentEntry[] } {
  const safe: AgentEntry[] = [];
  const skipped: AgentEntry[] = [];

  for (const agent of agents) {
    if (wouldAffectSelf(agent.tmuxTarget, selfPaneId, paneMap)) {
      skipped.push(agent);
    } else {
      safe.push(agent);
    }
  }

  return { safe, skipped };
}

/**
 * Check if cleaning up a worktree would kill the current process.
 * Checks all agent tmux targets and the worktree's own tmux window.
 */
export function wouldCleanupAffectSelf(
  wt: WorktreeEntry,
  selfPaneId: string,
  paneMap: Map<string, PaneInfo>,
): boolean {
  // Check worktree-level tmux window
  if (wt.tmuxWindow && wouldAffectSelf(wt.tmuxWindow, selfPaneId, paneMap)) {
    return true;
  }

  // Check each agent's tmux target
  for (const agent of Object.values(wt.agents)) {
    if (agent.tmuxTarget && wouldAffectSelf(agent.tmuxTarget, selfPaneId, paneMap)) {
      return true;
    }
  }

  return false;
}
