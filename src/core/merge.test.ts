import { describe, test, expect, vi, beforeEach } from 'vitest';
import { makeWorktree, makeAgent } from '../test-fixtures.js';
import type { Manifest } from '../types/manifest.js';

// ---- Mocks ----

let manifestState: Manifest;

vi.mock('./manifest.js', () => ({
  updateManifest: vi.fn(async (_root: string, updater: (m: Manifest) => Manifest | Promise<Manifest>) => {
    manifestState = await updater(structuredClone(manifestState));
    return manifestState;
  }),
}));

vi.mock('./worktree.js', () => ({
  getCurrentBranch: vi.fn(() => 'main'),
}));

vi.mock('./cleanup.js', () => ({
  cleanupWorktree: vi.fn(async () => ({ selfProtected: false, selfProtectedTargets: [] })),
}));

vi.mock('execa', () => ({
  execa: vi.fn(),
}));

vi.mock('../lib/env.js', () => ({
  execaEnv: {},
}));

// ---- Imports (after mocks) ----

import { mergeWorktree } from './merge.js';
import { getCurrentBranch } from './worktree.js';
import { cleanupWorktree } from './cleanup.js';
import { execa } from 'execa';

describe('mergeWorktree', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    const wt = makeWorktree({ id: 'wt-abc123', agents: {} });
    manifestState = {
      version: 1,
      projectRoot: '/tmp/project',
      sessionName: 'ppg',
      agents: {},
      worktrees: { 'wt-abc123': wt },
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    };
  });

  test('given valid worktree, should merge with squash and update manifest to merged', async () => {
    const wt = makeWorktree({ id: 'wt-abc123', agents: {} });

    const result = await mergeWorktree('/tmp/project', wt);

    expect(result.strategy).toBe('squash');
    expect(result.cleaned).toBe(true);
    expect(manifestState.worktrees['wt-abc123'].status).toBe('merged');
    expect(manifestState.worktrees['wt-abc123'].mergedAt).toBeDefined();
  });

  test('given no-ff strategy, should call git merge --no-ff', async () => {
    const wt = makeWorktree({ id: 'wt-abc123', agents: {} });

    await mergeWorktree('/tmp/project', wt, { strategy: 'no-ff' });

    const calls = vi.mocked(execa).mock.calls;
    const mergeCall = calls.find((c) => c[0] === 'git' && (c[1] as string[])?.[0] === 'merge');
    expect(mergeCall).toBeDefined();
    expect((mergeCall![1] as string[])).toContain('--no-ff');
  });

  test('given different current branch, should checkout base branch first', async () => {
    vi.mocked(getCurrentBranch).mockResolvedValueOnce('feature-x');
    const wt = makeWorktree({ id: 'wt-abc123', baseBranch: 'main', agents: {} });

    await mergeWorktree('/tmp/project', wt);

    const calls = vi.mocked(execa).mock.calls;
    const checkoutCall = calls.find((c) => c[0] === 'git' && (c[1] as string[])?.[0] === 'checkout');
    expect(checkoutCall).toBeDefined();
    expect((checkoutCall![1] as string[])).toContain('main');
  });

  test('given running agents without force, should throw AGENTS_RUNNING', async () => {
    const agent = makeAgent({ id: 'ag-running1', status: 'running' });
    const wt = makeWorktree({ id: 'wt-abc123', agents: { 'ag-running1': agent } });

    await expect(mergeWorktree('/tmp/project', wt)).rejects.toThrow('agent(s) still running');
  });

  test('given running agents with force, should merge anyway', async () => {
    const agent = makeAgent({ id: 'ag-running1', status: 'running' });
    const wt = makeWorktree({ id: 'wt-abc123', agents: { 'ag-running1': agent } });

    const result = await mergeWorktree('/tmp/project', wt, { force: true });

    expect(result.worktreeId).toBe('wt-abc123');
  });

  test('given cleanup false, should skip cleanup', async () => {
    const wt = makeWorktree({ id: 'wt-abc123', agents: {} });

    const result = await mergeWorktree('/tmp/project', wt, { cleanup: false });

    expect(result.cleaned).toBe(false);
    expect(vi.mocked(cleanupWorktree)).not.toHaveBeenCalled();
  });

  test('given git merge failure, should set status to failed and throw', async () => {
    const wt = makeWorktree({ id: 'wt-abc123', agents: {} });
    vi.mocked(execa).mockRejectedValueOnce(new Error('conflict'));

    await expect(mergeWorktree('/tmp/project', wt)).rejects.toThrow('Merge failed');
    expect(manifestState.worktrees['wt-abc123'].status).toBe('failed');
  });
});
