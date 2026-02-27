import { describe, test, expect, vi, beforeEach } from 'vitest';
import Fastify from 'fastify';
import type { FastifyInstance } from 'fastify';
import { makeWorktree, makeAgent } from '../../test-fixtures.js';
import type { Manifest } from '../../types/manifest.js';

// ---- Mocks ----

const mockManifest: Manifest = {
  version: 1,
  projectRoot: '/tmp/project',
  sessionName: 'ppg',
  worktrees: {},
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
};

vi.mock('../../core/manifest.js', () => ({
  requireManifest: vi.fn(),
  updateManifest: vi.fn(async (_root: string, updater: (m: Manifest) => Manifest | Promise<Manifest>) => {
    return updater(structuredClone(mockManifest));
  }),
  resolveWorktree: vi.fn(),
}));

vi.mock('../../core/agent.js', () => ({
  refreshAllAgentStatuses: vi.fn((m: Manifest) => m),
  killAgents: vi.fn(),
}));

vi.mock('../../core/worktree.js', () => ({
  getCurrentBranch: vi.fn(() => 'main'),
}));

vi.mock('../../core/cleanup.js', () => ({
  cleanupWorktree: vi.fn(),
}));

vi.mock('../../commands/pr.js', () => ({
  buildBodyFromResults: vi.fn(() => 'PR body'),
}));

vi.mock('execa', () => ({
  execa: vi.fn(() => ({ stdout: 'https://github.com/owner/repo/pull/1' })),
}));

vi.mock('../../lib/env.js', () => ({
  execaEnv: {},
}));

// ---- Imports (after mocks) ----

import { resolveWorktree } from '../../core/manifest.js';
import { killAgents } from '../../core/agent.js';
import { cleanupWorktree } from '../../core/cleanup.js';
import { getCurrentBranch } from '../../core/worktree.js';
import { execa } from 'execa';
import { worktreeRoutes } from './worktrees.js';

const PROJECT_ROOT = '/tmp/project';

async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify();
  app.decorate('projectRoot', PROJECT_ROOT);
  await app.register(worktreeRoutes, { prefix: '/api' });
  await app.ready();
  return app;
}

describe('worktreeRoutes', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockManifest.worktrees = {};
  });

  // ==================================================================
  // POST /api/worktrees/:id/merge
  // ==================================================================
  describe('POST /api/worktrees/:id/merge', () => {
    test('given valid worktree, should merge with squash strategy by default', async () => {
      const wt = makeWorktree({ id: 'wt-abc123', agents: {} });
      mockManifest.worktrees['wt-abc123'] = wt;
      vi.mocked(resolveWorktree).mockReturnValue(wt);

      const app = await buildApp();
      const res = await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-abc123/merge',
        payload: {},
      });

      expect(res.statusCode).toBe(200);
      const body = res.json();
      expect(body.success).toBe(true);
      expect(body.worktreeId).toBe('wt-abc123');
      expect(body.strategy).toBe('squash');
      expect(body.cleaned).toBe(true);
      expect(vi.mocked(cleanupWorktree)).toHaveBeenCalled();
    });

    test('given strategy no-ff, should merge with --no-ff', async () => {
      const wt = makeWorktree({ id: 'wt-abc123', agents: {} });
      mockManifest.worktrees['wt-abc123'] = wt;
      vi.mocked(resolveWorktree).mockReturnValue(wt);

      const app = await buildApp();
      const res = await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-abc123/merge',
        payload: { strategy: 'no-ff' },
      });

      expect(res.statusCode).toBe(200);
      expect(res.json().strategy).toBe('no-ff');

      // Should have called git merge --no-ff
      const execaCalls = vi.mocked(execa).mock.calls;
      const mergeCall = execaCalls.find((c) => c[0] === 'git' && (c[1] as string[])?.[0] === 'merge');
      expect(mergeCall).toBeDefined();
      expect((mergeCall![1] as string[])).toContain('--no-ff');
    });

    test('given cleanup false, should skip cleanup', async () => {
      const wt = makeWorktree({ id: 'wt-abc123', agents: {} });
      mockManifest.worktrees['wt-abc123'] = wt;
      vi.mocked(resolveWorktree).mockReturnValue(wt);

      const app = await buildApp();
      const res = await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-abc123/merge',
        payload: { cleanup: false },
      });

      expect(res.statusCode).toBe(200);
      expect(res.json().cleaned).toBe(false);
      expect(vi.mocked(cleanupWorktree)).not.toHaveBeenCalled();
    });

    test('given worktree not found, should return 404', async () => {
      vi.mocked(resolveWorktree).mockReturnValue(undefined as unknown as ReturnType<typeof resolveWorktree>);

      const app = await buildApp();
      const res = await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-nonexist/merge',
        payload: {},
      });

      expect(res.statusCode).toBe(404);
      expect(res.json().code).toBe('WORKTREE_NOT_FOUND');
    });

    test('given running agents without force, should return 409', async () => {
      const agent = makeAgent({ id: 'ag-running1', status: 'running' });
      const wt = makeWorktree({
        id: 'wt-abc123',
        agents: { 'ag-running1': agent },
      });
      mockManifest.worktrees['wt-abc123'] = wt;
      vi.mocked(resolveWorktree).mockReturnValue(wt);

      const app = await buildApp();
      const res = await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-abc123/merge',
        payload: {},
      });

      expect(res.statusCode).toBe(409);
      expect(res.json().code).toBe('AGENTS_RUNNING');
    });

    test('given running agents with force, should merge anyway', async () => {
      const agent = makeAgent({ id: 'ag-running1', status: 'running' });
      const wt = makeWorktree({
        id: 'wt-abc123',
        agents: { 'ag-running1': agent },
      });
      mockManifest.worktrees['wt-abc123'] = wt;
      vi.mocked(resolveWorktree).mockReturnValue(wt);

      const app = await buildApp();
      const res = await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-abc123/merge',
        payload: { force: true },
      });

      expect(res.statusCode).toBe(200);
      expect(res.json().success).toBe(true);
    });

    test('given git merge failure, should return 500 with MERGE_FAILED', async () => {
      const wt = makeWorktree({ id: 'wt-abc123', agents: {} });
      mockManifest.worktrees['wt-abc123'] = wt;
      vi.mocked(resolveWorktree).mockReturnValue(wt);
      vi.mocked(execa).mockRejectedValueOnce(new Error('conflict'));

      const app = await buildApp();
      const res = await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-abc123/merge',
        payload: {},
      });

      // getCurrentBranch returns 'main' which matches baseBranch, so no checkout call.
      // First execa call is git merge --squash which fails.
      expect(res.statusCode).toBe(500);
      expect(res.json().code).toBe('MERGE_FAILED');
    });
  });

  // ==================================================================
  // POST /api/worktrees/:id/kill
  // ==================================================================
  describe('POST /api/worktrees/:id/kill', () => {
    test('given worktree with running agents, should kill all running agents', async () => {
      const agent1 = makeAgent({ id: 'ag-run00001', status: 'running' });
      const agent2 = makeAgent({ id: 'ag-idle0001', status: 'idle' });
      const wt = makeWorktree({
        id: 'wt-abc123',
        agents: { 'ag-run00001': agent1, 'ag-idle0001': agent2 },
      });
      mockManifest.worktrees['wt-abc123'] = wt;
      vi.mocked(resolveWorktree).mockReturnValue(wt);

      const app = await buildApp();
      const res = await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-abc123/kill',
        payload: {},
      });

      expect(res.statusCode).toBe(200);
      const body = res.json();
      expect(body.success).toBe(true);
      expect(body.killed).toEqual(['ag-run00001']);
      expect(vi.mocked(killAgents)).toHaveBeenCalledWith([agent1]);
    });

    test('given worktree with no running agents, should return empty killed list', async () => {
      const agent = makeAgent({ id: 'ag-done0001', status: 'exited' });
      const wt = makeWorktree({
        id: 'wt-abc123',
        agents: { 'ag-done0001': agent },
      });
      mockManifest.worktrees['wt-abc123'] = wt;
      vi.mocked(resolveWorktree).mockReturnValue(wt);

      const app = await buildApp();
      const res = await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-abc123/kill',
        payload: {},
      });

      expect(res.statusCode).toBe(200);
      expect(res.json().killed).toEqual([]);
      expect(vi.mocked(killAgents)).toHaveBeenCalledWith([]);
    });

    test('given worktree not found, should return 404', async () => {
      vi.mocked(resolveWorktree).mockReturnValue(undefined as unknown as ReturnType<typeof resolveWorktree>);

      const app = await buildApp();
      const res = await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-nonexist/kill',
        payload: {},
      });

      expect(res.statusCode).toBe(404);
      expect(res.json().code).toBe('WORKTREE_NOT_FOUND');
    });
  });

  // ==================================================================
  // POST /api/worktrees/:id/pr
  // ==================================================================
  describe('POST /api/worktrees/:id/pr', () => {
    test('given valid worktree, should create PR and store URL', async () => {
      const wt = makeWorktree({ id: 'wt-abc123', agents: {} });
      mockManifest.worktrees['wt-abc123'] = wt;
      vi.mocked(resolveWorktree).mockReturnValue(wt);

      const app = await buildApp();
      const res = await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-abc123/pr',
        payload: { title: 'My PR', body: 'Description' },
      });

      expect(res.statusCode).toBe(200);
      const body = res.json();
      expect(body.success).toBe(true);
      expect(body.prUrl).toBe('https://github.com/owner/repo/pull/1');
      expect(body.worktreeId).toBe('wt-abc123');
    });

    test('given draft flag, should pass --draft to gh', async () => {
      const wt = makeWorktree({ id: 'wt-abc123', agents: {} });
      mockManifest.worktrees['wt-abc123'] = wt;
      vi.mocked(resolveWorktree).mockReturnValue(wt);

      const app = await buildApp();
      await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-abc123/pr',
        payload: { draft: true },
      });

      const ghCalls = vi.mocked(execa).mock.calls.filter((c) => c[0] === 'gh');
      const prCreateCall = ghCalls.find((c) => (c[1] as string[])?.includes('create'));
      expect(prCreateCall).toBeDefined();
      expect((prCreateCall![1] as string[])).toContain('--draft');
    });

    test('given worktree not found, should return 404', async () => {
      vi.mocked(resolveWorktree).mockReturnValue(undefined as unknown as ReturnType<typeof resolveWorktree>);

      const app = await buildApp();
      const res = await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-nonexist/pr',
        payload: {},
      });

      expect(res.statusCode).toBe(404);
      expect(res.json().code).toBe('WORKTREE_NOT_FOUND');
    });

    test('given gh not available, should return 502', async () => {
      const wt = makeWorktree({ id: 'wt-abc123', agents: {} });
      mockManifest.worktrees['wt-abc123'] = wt;
      vi.mocked(resolveWorktree).mockReturnValue(wt);

      // First call is gh --version which should fail
      vi.mocked(execa).mockRejectedValueOnce(new Error('gh not found'));

      const app = await buildApp();
      const res = await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-abc123/pr',
        payload: {},
      });

      expect(res.statusCode).toBe(502);
      expect(res.json().code).toBe('GH_NOT_FOUND');
    });

    test('given push failure, should return 400', async () => {
      const wt = makeWorktree({ id: 'wt-abc123', agents: {} });
      mockManifest.worktrees['wt-abc123'] = wt;
      vi.mocked(resolveWorktree).mockReturnValue(wt);

      // gh --version succeeds, git push fails
      vi.mocked(execa)
        .mockResolvedValueOnce({ stdout: 'gh version 2.0' } as never)
        .mockRejectedValueOnce(new Error('push rejected'));

      const app = await buildApp();
      const res = await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-abc123/pr',
        payload: {},
      });

      expect(res.statusCode).toBe(400);
      expect(res.json().code).toBe('INVALID_ARGS');
    });
  });
});
