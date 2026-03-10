import fs from 'node:fs';
import path from 'node:path';
import { readManifest } from '../../core/manifest.js';
import { checkAgentStatus } from '../../core/agent.js';
import { listSessionPanes, type PaneInfo } from '../../core/tmux.js';
import { manifestPath, ppgDir } from '../../lib/paths.js';
import type { AgentStatus, Manifest } from '../../types/manifest.js';

export type WsEvent =
  | { type: 'manifest:updated'; payload: Manifest }
  | { type: 'agent:status'; payload: { agentId: string; worktreeId: string; status: AgentStatus; previousStatus: AgentStatus } };

export type BroadcastFn = (event: WsEvent) => void;

export type ErrorFn = (error: unknown) => void;

export interface ManifestWatcher {
  stop(): void;
}

/**
 * Start watching manifest.json for changes and polling agent statuses.
 *
 * Two sources of change:
 * 1. `fs.watch` on manifest.json — fires `manifest:updated` (debounced 300ms)
 * 2. Status poll at `pollIntervalMs` — fires `agent:status` per changed agent
 *
 * Note: `manifest:updated` and `agent:status` are independent streams.
 * A file change that adds/removes agents won't produce `agent:status` events
 * until the next poll cycle. Consumers needing immediate agent awareness
 * should derive it from the `manifest:updated` payload.
 *
 * The watcher must start after `ppg init` — if manifest.json doesn't exist
 * at startup, the parent directory is watched and the file watcher is
 * established once the manifest appears.
 */
export function startManifestWatcher(
  projectRoot: string,
  broadcast: BroadcastFn,
  options?: { debounceMs?: number; pollIntervalMs?: number; onError?: ErrorFn },
): ManifestWatcher {
  const debounceMs = options?.debounceMs ?? 300;
  const pollIntervalMs = options?.pollIntervalMs ?? 3000;
  const onError = options?.onError;

  let debounceTimer: ReturnType<typeof setTimeout> | null = null;
  let previousStatuses = new Map<string, AgentStatus>();
  let polling = false;
  let stopped = false;

  // --- fs.watch on manifest.json (with directory fallback) ---
  const mPath = manifestPath(projectRoot);
  let fileWatcher: fs.FSWatcher | null = null;
  let dirWatcher: fs.FSWatcher | null = null;

  function onFsChange(): void {
    if (stopped) return;
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      if (stopped) return;
      onManifestFileChange().catch((err) => onError?.(err));
    }, debounceMs);
  }

  function watchManifestFile(): boolean {
    try {
      fileWatcher = fs.watch(mPath, onFsChange);
      fileWatcher.on('error', () => {});
      return true;
    } catch {
      return false;
    }
  }

  // Try to watch manifest directly; fall back to watching .ppg/ directory
  if (!watchManifestFile()) {
    try {
      const dir = ppgDir(projectRoot);
      dirWatcher = fs.watch(dir, (_event, filename) => {
        if (filename === path.basename(mPath) && !fileWatcher) {
          if (watchManifestFile()) {
            dirWatcher?.close();
            dirWatcher = null;
          }
          onFsChange();
        }
      });
      dirWatcher.on('error', () => {});
    } catch {
      // .ppg/ doesn't exist yet either — polling still works
    }
  }

  async function onManifestFileChange(): Promise<void> {
    try {
      const manifest = await readManifest(projectRoot);
      broadcast({ type: 'manifest:updated', payload: manifest });
    } catch (err) {
      onError?.(err);
    }
  }

  // --- Status polling ---
  const pollTimer = setInterval(() => {
    if (stopped) return;
    pollStatuses().catch((err) => onError?.(err));
  }, pollIntervalMs);

  async function pollStatuses(): Promise<void> {
    if (polling) return;
    polling = true;
    try {
      let manifest: Manifest;
      try {
        manifest = await readManifest(projectRoot);
      } catch (err) {
        onError?.(err);
        return;
      }

      let paneMap: Map<string, PaneInfo>;
      try {
        paneMap = await listSessionPanes(manifest.sessionName);
      } catch (err) {
        onError?.(err);
        return;
      }

      // Collect all agents with their worktree context
      const agents = Object.values(manifest.worktrees).flatMap((wt) =>
        Object.values(wt.agents).map((agent) => ({ agent, worktreeId: wt.id })),
      );

      // Check statuses in parallel (checkAgentStatus does no I/O when paneMap is provided)
      const results = await Promise.all(
        agents.map(({ agent }) =>
          checkAgentStatus(agent, projectRoot, paneMap).catch(() => null),
        ),
      );

      const nextStatuses = new Map<string, AgentStatus>();
      for (let i = 0; i < agents.length; i++) {
        const result = results[i];
        if (!result) continue;

        const { agent, worktreeId } = agents[i];
        nextStatuses.set(agent.id, result.status);

        const prev = previousStatuses.get(agent.id);
        if (prev !== undefined && prev !== result.status) {
          broadcast({
            type: 'agent:status',
            payload: { agentId: agent.id, worktreeId, status: result.status, previousStatus: prev },
          });
        }
      }
      previousStatuses = nextStatuses;
    } finally {
      polling = false;
    }
  }

  return {
    stop() {
      stopped = true;
      if (debounceTimer) clearTimeout(debounceTimer);
      if (fileWatcher) fileWatcher.close();
      if (dirWatcher) dirWatcher.close();
      clearInterval(pollTimer);
    },
  };
}
