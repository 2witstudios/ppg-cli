import { describe, test, expect, vi, beforeEach } from 'vitest';
import Fastify from 'fastify';
import type { FastifyInstance } from 'fastify';
import { makeWorktree, makeAgent } from '../../test-fixtures.js';
import type { Manifest } from '../../types/manifest.js';
import type { WorktreeEntry } from '../../types/manifest.js';

// ---- Mocks ----

const mockManifest: Manifest = {
  version: 1,
  projectRoot: '/tmp/project',
  sessionName: 'ppg',
  agents: {},
  worktrees: {},
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
};

vi.mock('../../core/manifest.js', () => ({
  updateManifest: vi.fn(async (_root: string, updater: (m: Manifest) => Manifest | Promise<Manifest>) => {
    return updater(structuredClone(mockManifest));
  }),
  resolveWorktree: vi.fn(),
}));

vi.mock('../../core/agent.js', () => ({
  refreshAllAgentStatuses: vi.fn((m: Manifest) => m),
}));

vi.mock('../../core/merge.js', () => ({
  mergeWorktree: vi.fn(async (_root: string, wt: WorktreeEntry, opts: Record<string, unknown> = {}) => ({
    worktreeId: wt.id,
    branch: wt.branch,
    baseBranch: wt.baseBranch,
    strategy: (opts.strategy as string) ?? 'squash',
    cleaned: opts.cleanup !== false,
    selfProtected: false,
  })),
}));

vi.mock('../../core/kill.js', () => ({
  killWorktreeAgents: vi.fn(async (_root: string, wt: WorktreeEntry) => {
    const killed = Object.values(wt.agents)
      .filter((a) => a.status === 'running')
      .map((a) => a.id);
    return { worktreeId: wt.id, killed };
  }),
}));

vi.mock('../../core/pr.js', () => ({
  createWorktreePr: vi.fn(async (_root: string, wt: WorktreeEntry) => ({
    worktreeId: wt.id,
    branch: wt.branch,
    baseBranch: wt.baseBranch,
    prUrl: 'https://github.com/owner/repo/pull/1',
  })),
}));

// ---- Imports (after mocks) ----

import { resolveWorktree, updateManifest } from '../../core/manifest.js';
import { mergeWorktree } from '../../core/merge.js';
import { killWorktreeAgents } from '../../core/kill.js';
import { createWorktreePr } from '../../core/pr.js';
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
      expect(vi.mocked(mergeWorktree)).toHaveBeenCalledWith(
        PROJECT_ROOT, wt, { strategy: undefined, cleanup: undefined, force: undefined },
      );
    });

    test('given strategy no-ff, should pass strategy to mergeWorktree', async () => {
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
      expect(vi.mocked(mergeWorktree)).toHaveBeenCalledWith(
        PROJECT_ROOT, wt, expect.objectContaining({ strategy: 'no-ff' }),
      );
    });

    test('given cleanup false, should pass cleanup false', async () => {
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
      expect(vi.mocked(mergeWorktree)).toHaveBeenCalledWith(
        PROJECT_ROOT, wt, expect.objectContaining({ cleanup: false }),
      );
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

    test('given AGENTS_RUNNING error from core, should return 409', async () => {
      const wt = makeWorktree({ id: 'wt-abc123', agents: {} });
      mockManifest.worktrees['wt-abc123'] = wt;
      vi.mocked(resolveWorktree).mockReturnValue(wt);

      const { PpgError } = await import('../../lib/errors.js');
      vi.mocked(mergeWorktree).mockRejectedValueOnce(
        new PpgError('1 agent(s) still running', 'AGENTS_RUNNING'),
      );

      const app = await buildApp();
      const res = await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-abc123/merge',
        payload: {},
      });

      expect(res.statusCode).toBe(409);
      expect(res.json().code).toBe('AGENTS_RUNNING');
    });

    test('given force flag, should pass force to mergeWorktree', async () => {
      const wt = makeWorktree({ id: 'wt-abc123', agents: {} });
      mockManifest.worktrees['wt-abc123'] = wt;
      vi.mocked(resolveWorktree).mockReturnValue(wt);

      const app = await buildApp();
      const res = await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-abc123/merge',
        payload: { force: true },
      });

      expect(res.statusCode).toBe(200);
      expect(vi.mocked(mergeWorktree)).toHaveBeenCalledWith(
        PROJECT_ROOT, wt, expect.objectContaining({ force: true }),
      );
    });

    test('given MERGE_FAILED error from core, should return 500', async () => {
      const wt = makeWorktree({ id: 'wt-abc123', agents: {} });
      mockManifest.worktrees['wt-abc123'] = wt;
      vi.mocked(resolveWorktree).mockReturnValue(wt);

      const { MergeFailedError } = await import('../../lib/errors.js');
      vi.mocked(mergeWorktree).mockRejectedValueOnce(
        new MergeFailedError('Merge failed: conflict'),
      );

      const app = await buildApp();
      const res = await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-abc123/merge',
        payload: {},
      });

      expect(res.statusCode).toBe(500);
      expect(res.json().code).toBe('MERGE_FAILED');
    });
  });

  // ==================================================================
  // POST /api/worktrees/:id/kill
  // ==================================================================
  describe('POST /api/worktrees/:id/kill', () => {
    test('given worktree with running agents, should kill via core and return killed list', async () => {
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
      expect(vi.mocked(killWorktreeAgents)).toHaveBeenCalledWith(PROJECT_ROOT, wt);
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
    test('given valid worktree, should create PR and return URL', async () => {
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
      expect(vi.mocked(createWorktreePr)).toHaveBeenCalledWith(
        PROJECT_ROOT, wt, { title: 'My PR', body: 'Description', draft: undefined },
      );
    });

    test('given draft flag, should pass draft to createWorktreePr', async () => {
      const wt = makeWorktree({ id: 'wt-abc123', agents: {} });
      mockManifest.worktrees['wt-abc123'] = wt;
      vi.mocked(resolveWorktree).mockReturnValue(wt);

      const app = await buildApp();
      await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-abc123/pr',
        payload: { draft: true },
      });

      expect(vi.mocked(createWorktreePr)).toHaveBeenCalledWith(
        PROJECT_ROOT, wt, expect.objectContaining({ draft: true }),
      );
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

    test('given GH_NOT_FOUND error from core, should return 502', async () => {
      const wt = makeWorktree({ id: 'wt-abc123', agents: {} });
      mockManifest.worktrees['wt-abc123'] = wt;
      vi.mocked(resolveWorktree).mockReturnValue(wt);

      const { GhNotFoundError } = await import('../../lib/errors.js');
      vi.mocked(createWorktreePr).mockRejectedValueOnce(new GhNotFoundError());

      const app = await buildApp();
      const res = await app.inject({
        method: 'POST',
        url: '/api/worktrees/wt-abc123/pr',
        payload: {},
      });

      expect(res.statusCode).toBe(502);
      expect(res.json().code).toBe('GH_NOT_FOUND');
    });

    test('given INVALID_ARGS error from core, should return 400', async () => {
      const wt = makeWorktree({ id: 'wt-abc123', agents: {} });
      mockManifest.worktrees['wt-abc123'] = wt;
      vi.mocked(resolveWorktree).mockReturnValue(wt);

      const { PpgError } = await import('../../lib/errors.js');
      vi.mocked(createWorktreePr).mockRejectedValueOnce(
        new PpgError('Failed to push', 'INVALID_ARGS'),
      );

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
