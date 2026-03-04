import { describe, test, expect, vi, beforeEach, afterEach } from 'vitest';
import { makeAgent, makeManifest, makeWorktree } from '../../test-fixtures.js';
import type { WsEvent } from './watcher.js';

// Mock fs (synchronous watch API)
vi.mock('node:fs', () => ({
  default: {
    watch: vi.fn((_path: string, _cb: (...args: unknown[]) => void) => ({
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
  ppgDir: vi.fn(() => '/tmp/project/.ppg'),
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
      const manifest = makeManifest({ projectRoot: PROJECT_ROOT, worktrees: { [wt.id]: wt } });
      mockedReadManifest.mockResolvedValue(manifest);
      mockedCheckAgentStatus.mockResolvedValue({ status: 'running' });

      const events: WsEvent[] = [];
      const watcher = startManifestWatcher(PROJECT_ROOT, (e) => events.push(e), {
        debounceMs: 300,
        pollIntervalMs: 60_000, // effectively disable polling for this test
      });

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
      const manifest = makeManifest({ projectRoot: PROJECT_ROOT });
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

      const errors: unknown[] = [];
      const events: WsEvent[] = [];
      const watcher = startManifestWatcher(PROJECT_ROOT, (e) => events.push(e), {
        debounceMs: 300,
        pollIntervalMs: 60_000,
        onError: (err) => errors.push(err),
      });

      triggerFsWatch();
      await vi.advanceTimersByTimeAsync(350);

      expect(events).toHaveLength(0);
      expect(errors).toHaveLength(1);
      expect(errors[0]).toBeInstanceOf(SyntaxError);

      watcher.stop();
    });
  });

  describe('status polling', () => {
    test('given agent status change, should broadcast agent:status', async () => {
      const agent = makeAgent({ id: 'ag-aaa11111', status: 'running' });
      const wt = makeWorktree({ id: 'wt-abc123', agents: { [agent.id]: agent } });
      const manifest = makeManifest({ projectRoot: PROJECT_ROOT, worktrees: { [wt.id]: wt } });
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

    test('given multiple agents across worktrees, should broadcast each change', async () => {
      const agent1 = makeAgent({ id: 'ag-aaa11111', status: 'running', tmuxTarget: 'ppg:1.0' });
      const agent2 = makeAgent({ id: 'ag-bbb22222', status: 'running', tmuxTarget: 'ppg:2.0' });
      const wt1 = makeWorktree({ id: 'wt-aaa111', name: 'auth', agents: { [agent1.id]: agent1 } });
      const wt2 = makeWorktree({ id: 'wt-bbb222', name: 'api', agents: { [agent2.id]: agent2 } });
      const manifest = makeManifest({
        projectRoot: PROJECT_ROOT,
        worktrees: { [wt1.id]: wt1, [wt2.id]: wt2 },
      });
      mockedReadManifest.mockResolvedValue(manifest);

      // First poll: both running. Second poll: agent1 idle, agent2 gone
      mockedCheckAgentStatus
        .mockResolvedValueOnce({ status: 'running' })
        .mockResolvedValueOnce({ status: 'running' })
        .mockResolvedValueOnce({ status: 'idle' })
        .mockResolvedValueOnce({ status: 'gone' });

      const events: WsEvent[] = [];
      const watcher = startManifestWatcher(PROJECT_ROOT, (e) => events.push(e), {
        debounceMs: 300,
        pollIntervalMs: 1000,
      });

      // First poll — baseline
      await vi.advanceTimersByTimeAsync(1000);
      expect(events).toHaveLength(0);

      // Second poll — both changed
      await vi.advanceTimersByTimeAsync(1000);
      expect(events).toHaveLength(2);

      const statusEvents = events.filter((e) => e.type === 'agent:status');
      expect(statusEvents).toHaveLength(2);

      const payloads = statusEvents.map((e) => e.payload);
      expect(payloads).toContainEqual({
        agentId: 'ag-aaa11111',
        worktreeId: 'wt-aaa111',
        status: 'idle',
        previousStatus: 'running',
      });
      expect(payloads).toContainEqual({
        agentId: 'ag-bbb22222',
        worktreeId: 'wt-bbb222',
        status: 'gone',
        previousStatus: 'running',
      });

      watcher.stop();
    });

    test('given agent removed between polls, should not emit stale event', async () => {
      const agent = makeAgent({ id: 'ag-aaa11111', status: 'running' });
      const wt = makeWorktree({ id: 'wt-abc123', agents: { [agent.id]: agent } });
      const manifestWithAgent = makeManifest({ projectRoot: PROJECT_ROOT, worktrees: { [wt.id]: wt } });
      const manifestEmpty = makeManifest({ projectRoot: PROJECT_ROOT, worktrees: {} });

      mockedCheckAgentStatus.mockResolvedValue({ status: 'running' });

      // First poll sees agent, second poll agent's worktree is gone
      mockedReadManifest
        .mockResolvedValueOnce(manifestWithAgent)
        .mockResolvedValueOnce(manifestEmpty);

      const events: WsEvent[] = [];
      const watcher = startManifestWatcher(PROJECT_ROOT, (e) => events.push(e), {
        debounceMs: 300,
        pollIntervalMs: 1000,
      });

      // First poll — baseline with agent
      await vi.advanceTimersByTimeAsync(1000);
      expect(events).toHaveLength(0);

      // Second poll — agent gone from manifest, no stale event emitted
      await vi.advanceTimersByTimeAsync(1000);
      expect(events).toHaveLength(0);

      watcher.stop();
    });

    test('given no status change, should not broadcast', async () => {
      const agent = makeAgent({ id: 'ag-aaa11111', status: 'running' });
      const wt = makeWorktree({ id: 'wt-abc123', agents: { [agent.id]: agent } });
      const manifest = makeManifest({ projectRoot: PROJECT_ROOT, worktrees: { [wt.id]: wt } });
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

    test('given manifest read failure during poll, should skip cycle and report error', async () => {
      const readError = new Error('ENOENT');
      mockedReadManifest.mockRejectedValue(readError);

      const errors: unknown[] = [];
      const events: WsEvent[] = [];
      const watcher = startManifestWatcher(PROJECT_ROOT, (e) => events.push(e), {
        debounceMs: 300,
        pollIntervalMs: 1000,
        onError: (err) => errors.push(err),
      });

      await vi.advanceTimersByTimeAsync(1000);
      expect(events).toHaveLength(0);
      expect(errors).toHaveLength(1);
      expect(errors[0]).toBe(readError);

      watcher.stop();
    });

    test('given tmux unavailable during poll, should skip cycle and report error', async () => {
      const manifest = makeManifest({ projectRoot: PROJECT_ROOT });
      mockedReadManifest.mockResolvedValue(manifest);
      const tmuxError = new Error('tmux not found');
      mockedListSessionPanes.mockRejectedValue(tmuxError);

      const errors: unknown[] = [];
      const events: WsEvent[] = [];
      const watcher = startManifestWatcher(PROJECT_ROOT, (e) => events.push(e), {
        debounceMs: 300,
        pollIntervalMs: 1000,
        onError: (err) => errors.push(err),
      });

      await vi.advanceTimersByTimeAsync(1000);
      expect(events).toHaveLength(0);
      expect(errors).toHaveLength(1);
      expect(errors[0]).toBe(tmuxError);

      watcher.stop();
    });
  });

  describe('overlap guard', () => {
    test('given slow poll, should skip overlapping tick', async () => {
      const agent = makeAgent({ id: 'ag-aaa11111', status: 'running' });
      const wt = makeWorktree({ id: 'wt-abc123', agents: { [agent.id]: agent } });
      const manifest = makeManifest({ projectRoot: PROJECT_ROOT, worktrees: { [wt.id]: wt } });

      // readManifest takes 1500ms on first call (longer than pollInterval)
      let callCount = 0;
      mockedReadManifest.mockImplementation(() => {
        callCount++;
        if (callCount === 1) {
          return new Promise((resolve) => setTimeout(() => resolve(manifest), 1500));
        }
        return Promise.resolve(manifest);
      });
      mockedCheckAgentStatus.mockResolvedValue({ status: 'running' });

      const events: WsEvent[] = [];
      const watcher = startManifestWatcher(PROJECT_ROOT, (e) => events.push(e), {
        debounceMs: 300,
        pollIntervalMs: 1000,
      });

      // First tick at 1000ms starts a slow poll
      await vi.advanceTimersByTimeAsync(1000);
      // Second tick at 2000ms — poll still running, should be skipped
      await vi.advanceTimersByTimeAsync(1000);
      // Finish slow poll at 2500ms
      await vi.advanceTimersByTimeAsync(500);

      // readManifest called once for the slow poll, second tick was skipped
      expect(callCount).toBe(1);

      watcher.stop();
    });
  });

  describe('cleanup', () => {
    test('stop should clear all timers and close watcher', async () => {
      const manifest = makeManifest({ projectRoot: PROJECT_ROOT });
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
      expect(watchResults.length).toBeGreaterThan(0);
      const fsWatcher = watchResults[0].value as { close: ReturnType<typeof vi.fn> };
      expect(fsWatcher.close).toHaveBeenCalled();
    });
  });
});
