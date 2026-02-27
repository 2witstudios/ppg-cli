import { describe, test, expect, vi, beforeEach, afterEach } from 'vitest';
import { makeAgent, makeWorktree } from '../../test-fixtures.js';
import type { WsEvent } from './watcher.js';
import type { Manifest } from '../../types/manifest.js';

// Mock fs (synchronous watch API)
vi.mock('node:fs', () => ({
  default: {
    watch: vi.fn((_path: string, _cb: () => void) => ({
      on: vi.fn(),
      close: vi.fn(),
    })),
  },
}));

// Mock core modules
vi.mock('../../core/manifest.js', () => ({
  readManifest: vi.fn(),
}));

vi.mock('../../core/agent.js', () => ({
  checkAgentStatus: vi.fn(),
}));

vi.mock('../../core/tmux.js', () => ({
  listSessionPanes: vi.fn(),
}));

vi.mock('../../lib/paths.js', () => ({
  manifestPath: vi.fn(() => '/tmp/project/.ppg/manifest.json'),
}));

import nodefs from 'node:fs';
import { readManifest } from '../../core/manifest.js';
import { checkAgentStatus } from '../../core/agent.js';
import { listSessionPanes } from '../../core/tmux.js';
import { startManifestWatcher } from './watcher.js';

const mockedReadManifest = vi.mocked(readManifest);
const mockedCheckAgentStatus = vi.mocked(checkAgentStatus);
const mockedListSessionPanes = vi.mocked(listSessionPanes);
const mockedFsWatch = vi.mocked(nodefs.watch);

const PROJECT_ROOT = '/tmp/project';

function makeManifest(overrides?: Partial<Manifest>): Manifest {
  return {
    version: 1,
    projectRoot: PROJECT_ROOT,
    sessionName: 'ppg',
    worktrees: {},
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  };
}

/** Trigger the most recent fs.watch callback (simulates file change) */
function triggerFsWatch(): void {
  const calls = mockedFsWatch.mock.calls;
  if (calls.length > 0) {
    const cb = calls[calls.length - 1][1] as () => void;
    cb();
  }
}

beforeEach(() => {
  vi.useFakeTimers();
  vi.clearAllMocks();
  mockedListSessionPanes.mockResolvedValue(new Map());
});

afterEach(() => {
  vi.useRealTimers();
});

describe('startManifestWatcher', () => {
  describe('fs.watch debounce', () => {
    test('given file change, should broadcast manifest:updated after debounce', async () => {
      const agent = makeAgent({ id: 'ag-aaa11111', status: 'running' });
      const wt = makeWorktree({ id: 'wt-abc123', agents: { [agent.id]: agent } });
      const manifest = makeManifest({ worktrees: { [wt.id]: wt } });
      mockedReadManifest.mockResolvedValue(manifest);
      mockedCheckAgentStatus.mockResolvedValue({ status: 'running' });

      const events: WsEvent[] = [];
      const watcher = startManifestWatcher(PROJECT_ROOT, (e) => events.push(e), {
        debounceMs: 300,
        pollIntervalMs: 60_000, // effectively disable polling for this test
      });

      // Trigger fs.watch callback
      triggerFsWatch();

      // Before debounce fires — no event yet
      expect(events).toHaveLength(0);

      // Advance past debounce
      await vi.advanceTimersByTimeAsync(350);

      expect(events).toHaveLength(1);
      expect(events[0].type).toBe('manifest:updated');
      expect(events[0].payload).toEqual(manifest);

      watcher.stop();
    });

    test('given rapid file changes, should debounce to single broadcast', async () => {
      const manifest = makeManifest();
      mockedReadManifest.mockResolvedValue(manifest);

      const events: WsEvent[] = [];
      const watcher = startManifestWatcher(PROJECT_ROOT, (e) => events.push(e), {
        debounceMs: 300,
        pollIntervalMs: 60_000,
      });

      // Three rapid changes
      triggerFsWatch();
      await vi.advanceTimersByTimeAsync(100);
      triggerFsWatch();
      await vi.advanceTimersByTimeAsync(100);
      triggerFsWatch();

      // Advance past debounce from last trigger
      await vi.advanceTimersByTimeAsync(350);

      expect(events).toHaveLength(1);
      expect(events[0].type).toBe('manifest:updated');

      watcher.stop();
    });

    test('given manifest read error during file change, should not broadcast', async () => {
      mockedReadManifest.mockRejectedValue(new SyntaxError('Unexpected end of JSON'));

      const events: WsEvent[] = [];
      const watcher = startManifestWatcher(PROJECT_ROOT, (e) => events.push(e), {
        debounceMs: 300,
        pollIntervalMs: 60_000,
      });

      triggerFsWatch();
      await vi.advanceTimersByTimeAsync(350);

      expect(events).toHaveLength(0);

      watcher.stop();
    });
  });

  describe('status polling', () => {
    test('given agent status change, should broadcast agent:status', async () => {
      const agent = makeAgent({ id: 'ag-aaa11111', status: 'running' });
      const wt = makeWorktree({ id: 'wt-abc123', agents: { [agent.id]: agent } });
      const manifest = makeManifest({ worktrees: { [wt.id]: wt } });
      mockedReadManifest.mockResolvedValue(manifest);

      // First poll: running, second poll: idle
      mockedCheckAgentStatus
        .mockResolvedValueOnce({ status: 'running' })
        .mockResolvedValueOnce({ status: 'idle' });

      const events: WsEvent[] = [];
      const watcher = startManifestWatcher(PROJECT_ROOT, (e) => events.push(e), {
        debounceMs: 300,
        pollIntervalMs: 1000,
      });

      // First poll — establishes baseline, no change event
      await vi.advanceTimersByTimeAsync(1000);
      expect(events).toHaveLength(0);

      // Second poll — status changed from running → idle
      await vi.advanceTimersByTimeAsync(1000);
      expect(events).toHaveLength(1);
      expect(events[0]).toEqual({
        type: 'agent:status',
        payload: {
          agentId: 'ag-aaa11111',
          worktreeId: 'wt-abc123',
          status: 'idle',
          previousStatus: 'running',
        },
      });

      watcher.stop();
    });

    test('given no status change, should not broadcast', async () => {
      const agent = makeAgent({ id: 'ag-aaa11111', status: 'running' });
      const wt = makeWorktree({ id: 'wt-abc123', agents: { [agent.id]: agent } });
      const manifest = makeManifest({ worktrees: { [wt.id]: wt } });
      mockedReadManifest.mockResolvedValue(manifest);
      mockedCheckAgentStatus.mockResolvedValue({ status: 'running' });

      const events: WsEvent[] = [];
      const watcher = startManifestWatcher(PROJECT_ROOT, (e) => events.push(e), {
        debounceMs: 300,
        pollIntervalMs: 1000,
      });

      // Two polls — same status each time
      await vi.advanceTimersByTimeAsync(1000);
      await vi.advanceTimersByTimeAsync(1000);

      expect(events).toHaveLength(0);

      watcher.stop();
    });

    test('given manifest read failure during poll, should skip cycle', async () => {
      mockedReadManifest.mockRejectedValue(new Error('ENOENT'));

      const events: WsEvent[] = [];
      const watcher = startManifestWatcher(PROJECT_ROOT, (e) => events.push(e), {
        debounceMs: 300,
        pollIntervalMs: 1000,
      });

      await vi.advanceTimersByTimeAsync(1000);
      expect(events).toHaveLength(0);

      watcher.stop();
    });

    test('given tmux unavailable during poll, should skip cycle', async () => {
      const manifest = makeManifest();
      mockedReadManifest.mockResolvedValue(manifest);
      mockedListSessionPanes.mockRejectedValue(new Error('tmux not found'));

      const events: WsEvent[] = [];
      const watcher = startManifestWatcher(PROJECT_ROOT, (e) => events.push(e), {
        debounceMs: 300,
        pollIntervalMs: 1000,
      });

      await vi.advanceTimersByTimeAsync(1000);
      expect(events).toHaveLength(0);

      watcher.stop();
    });
  });

  describe('cleanup', () => {
    test('stop should clear all timers and close watcher', async () => {
      const manifest = makeManifest();
      mockedReadManifest.mockResolvedValue(manifest);

      const events: WsEvent[] = [];
      const watcher = startManifestWatcher(PROJECT_ROOT, (e) => events.push(e), {
        debounceMs: 300,
        pollIntervalMs: 1000,
      });

      watcher.stop();

      // Trigger fs.watch and advance timers — nothing should fire
      triggerFsWatch();
      await vi.advanceTimersByTimeAsync(5000);

      expect(events).toHaveLength(0);

      // Verify fs.watch close was called
      const watchResults = mockedFsWatch.mock.results;
      if (watchResults.length > 0) {
        const fsWatcher = watchResults[0].value as { close: ReturnType<typeof vi.fn> };
        expect(fsWatcher.close).toHaveBeenCalled();
      }
    });
  });
});
