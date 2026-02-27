import fs from 'node:fs';
import { readManifest } from '../../core/manifest.js';
import { checkAgentStatus } from '../../core/agent.js';
import { listSessionPanes } from '../../core/tmux.js';
import { manifestPath } from '../../lib/paths.js';
import type { AgentStatus, Manifest } from '../../types/manifest.js';

export interface WsEvent {
  type: 'manifest:updated' | 'agent:status';
  payload: unknown;
}

export type BroadcastFn = (event: WsEvent) => void;

export interface ManifestWatcher {
  stop(): void;
}

/**
 * Start watching manifest.json for changes and polling agent statuses.
 *
 * Two sources of change:
 * 1. `fs.watch` on manifest.json — fires `manifest:updated` (debounced 300ms)
 * 2. Status poll at `pollIntervalMs` — fires `agent:status` per changed agent
 */
export function startManifestWatcher(
  projectRoot: string,
  broadcast: BroadcastFn,
  options?: { debounceMs?: number; pollIntervalMs?: number },
): ManifestWatcher {
  const debounceMs = options?.debounceMs ?? 300;
  const pollIntervalMs = options?.pollIntervalMs ?? 3000;

  let debounceTimer: ReturnType<typeof setTimeout> | null = null;
  let previousStatuses = new Map<string, AgentStatus>();
  let stopped = false;

  // --- fs.watch on manifest.json ---
  const mPath = manifestPath(projectRoot);
  let watcher: fs.FSWatcher | null = null;
  try {
    watcher = fs.watch(mPath, () => {
      if (stopped) return;
      if (debounceTimer) clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        if (stopped) return;
        onManifestFileChange();
      }, debounceMs);
    });
    watcher.on('error', () => {
      // File may be deleted or inaccessible — silently ignore
    });
  } catch {
    // manifest.json may not exist yet — that's OK
  }

  async function onManifestFileChange(): Promise<void> {
    try {
      const manifest = await readManifest(projectRoot);
      broadcast({ type: 'manifest:updated', payload: manifest });
    } catch {
      // In-flight write or corrupted JSON — skip this cycle
    }
  }

  // --- Status polling ---
  const pollTimer = setInterval(() => {
    if (stopped) return;
    pollStatuses();
  }, pollIntervalMs);

  async function pollStatuses(): Promise<void> {
    let manifest: Manifest;
    try {
      manifest = await readManifest(projectRoot);
    } catch {
      return; // manifest unreadable — skip
    }

    // Batch-fetch pane info
    let paneMap: Map<string, import('../../core/tmux.js').PaneInfo> | undefined;
    try {
      paneMap = await listSessionPanes(manifest.sessionName);
    } catch {
      return; // tmux unavailable — skip
    }

    // Check each agent's live status
    const nextStatuses = new Map<string, AgentStatus>();
    for (const wt of Object.values(manifest.worktrees)) {
      for (const agent of Object.values(wt.agents)) {
        try {
          const { status } = await checkAgentStatus(agent, projectRoot, paneMap);
          nextStatuses.set(agent.id, status);

          const prev = previousStatuses.get(agent.id);
          if (prev !== undefined && prev !== status) {
            broadcast({
              type: 'agent:status',
              payload: { agentId: agent.id, worktreeId: wt.id, status, previousStatus: prev },
            });
          }
        } catch {
          // Individual agent check failed — skip
        }
      }
    }
    previousStatuses = nextStatuses;
  }

  return {
    stop() {
      stopped = true;
      if (debounceTimer) clearTimeout(debounceTimer);
      if (watcher) watcher.close();
      clearInterval(pollTimer);
    },
  };
}
