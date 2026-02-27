import { describe, test, expect, vi, beforeEach } from 'vitest';
import Fastify from 'fastify';
import type { FastifyInstance } from 'fastify';
import statusRoutes from './status.js';
import { makeWorktree, makeAgent } from '../../test-fixtures.js';
import type { Manifest } from '../../types/manifest.js';

const PROJECT_ROOT = '/tmp/project';
const TOKEN = 'test-token-123';

const mockManifest: Manifest = {
  version: 1,
  projectRoot: PROJECT_ROOT,
  sessionName: 'ppg-test',
  worktrees: {
    'wt-abc123': makeWorktree({
      agents: {
        'ag-test1234': makeAgent(),
      },
    }),
  },
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
};

vi.mock('../../core/manifest.js', () => ({
  requireManifest: vi.fn(),
  resolveWorktree: vi.fn(),
  updateManifest: vi.fn(),
}));

vi.mock('../../core/agent.js', () => ({
  refreshAllAgentStatuses: vi.fn((m: Manifest) => m),
}));

vi.mock('execa', () => ({
  execa: vi.fn(),
}));

import { requireManifest, resolveWorktree, updateManifest } from '../../core/manifest.js';
import { refreshAllAgentStatuses } from '../../core/agent.js';
import { execa } from 'execa';

const mockedUpdateManifest = vi.mocked(updateManifest);
const mockedRequireManifest = vi.mocked(requireManifest);
const mockedResolveWorktree = vi.mocked(resolveWorktree);
const mockedRefreshAllAgentStatuses = vi.mocked(refreshAllAgentStatuses);
const mockedExeca = vi.mocked(execa);

function buildApp(): FastifyInstance {
  const app = Fastify();
  app.register(statusRoutes, { projectRoot: PROJECT_ROOT, bearerToken: TOKEN });
  return app;
}

describe('status routes', () => {
  beforeEach(() => {
    vi.clearAllMocks();

    mockedUpdateManifest.mockImplementation(async (_root, updater) => {
      return updater(structuredClone(mockManifest));
    });
    mockedRequireManifest.mockResolvedValue(structuredClone(mockManifest));
    mockedRefreshAllAgentStatuses.mockImplementation(async (m) => m);
  });

  describe('authentication', () => {
    test('given no auth header, should return 401', async () => {
      const app = buildApp();
      const res = await app.inject({ method: 'GET', url: '/api/status' });
      expect(res.statusCode).toBe(401);
      expect(res.json()).toEqual({ error: 'Unauthorized' });
    });

    test('given wrong token, should return 401', async () => {
      const app = buildApp();
      const res = await app.inject({
        method: 'GET',
        url: '/api/status',
        headers: { authorization: 'Bearer wrong-token' },
      });
      expect(res.statusCode).toBe(401);
    });

    test('given valid token, should return 200', async () => {
      const app = buildApp();
      const res = await app.inject({
        method: 'GET',
        url: '/api/status',
        headers: { authorization: `Bearer ${TOKEN}` },
      });
      expect(res.statusCode).toBe(200);
    });
  });

  describe('GET /api/status', () => {
    test('should return full manifest with lifecycle', async () => {
      const app = buildApp();
      const res = await app.inject({
        method: 'GET',
        url: '/api/status',
        headers: { authorization: `Bearer ${TOKEN}` },
      });

      expect(res.statusCode).toBe(200);
      const body = res.json();
      expect(body.session).toBe('ppg-test');
      expect(body.worktrees['wt-abc123']).toBeDefined();
      expect(body.worktrees['wt-abc123'].lifecycle).toBe('busy');
    });

    test('should call refreshAllAgentStatuses', async () => {
      const app = buildApp();
      await app.inject({
        method: 'GET',
        url: '/api/status',
        headers: { authorization: `Bearer ${TOKEN}` },
      });

      expect(mockedRefreshAllAgentStatuses).toHaveBeenCalled();
    });
  });

  describe('GET /api/worktrees/:id', () => {
    test('given valid worktree id, should return worktree detail', async () => {
      mockedResolveWorktree.mockReturnValue(mockManifest.worktrees['wt-abc123']);

      const app = buildApp();
      const res = await app.inject({
        method: 'GET',
        url: '/api/worktrees/wt-abc123',
        headers: { authorization: `Bearer ${TOKEN}` },
      });

      expect(res.statusCode).toBe(200);
      const body = res.json();
      expect(body.id).toBe('wt-abc123');
      expect(body.name).toBe('feature-auth');
      expect(body.lifecycle).toBe('busy');
    });

    test('given worktree name, should resolve by name', async () => {
      mockedResolveWorktree.mockReturnValue(mockManifest.worktrees['wt-abc123']);

      const app = buildApp();
      const res = await app.inject({
        method: 'GET',
        url: '/api/worktrees/feature-auth',
        headers: { authorization: `Bearer ${TOKEN}` },
      });

      expect(res.statusCode).toBe(200);
      expect(mockedResolveWorktree).toHaveBeenCalledWith(expect.anything(), 'feature-auth');
    });

    test('given unknown worktree, should return 404', async () => {
      mockedResolveWorktree.mockReturnValue(undefined);

      const app = buildApp();
      const res = await app.inject({
        method: 'GET',
        url: '/api/worktrees/wt-unknown',
        headers: { authorization: `Bearer ${TOKEN}` },
      });

      expect(res.statusCode).toBe(404);
      expect(res.json()).toEqual({ error: 'Worktree not found: wt-unknown' });
    });
  });

  describe('GET /api/worktrees/:id/diff', () => {
    test('given valid worktree, should return numstat diff', async () => {
      mockedResolveWorktree.mockReturnValue(mockManifest.worktrees['wt-abc123']);
      mockedExeca.mockResolvedValue({
        stdout: '10\t2\tsrc/index.ts\n5\t0\tsrc/utils.ts',
      } as never);

      const app = buildApp();
      const res = await app.inject({
        method: 'GET',
        url: '/api/worktrees/wt-abc123/diff',
        headers: { authorization: `Bearer ${TOKEN}` },
      });

      expect(res.statusCode).toBe(200);
      const body = res.json();
      expect(body.worktreeId).toBe('wt-abc123');
      expect(body.branch).toBe('ppg/feature-auth');
      expect(body.baseBranch).toBe('main');
      expect(body.files).toEqual([
        { file: 'src/index.ts', added: 10, removed: 2 },
        { file: 'src/utils.ts', added: 5, removed: 0 },
      ]);
    });

    test('given empty diff, should return empty files array', async () => {
      mockedResolveWorktree.mockReturnValue(mockManifest.worktrees['wt-abc123']);
      mockedExeca.mockResolvedValue({ stdout: '' } as never);

      const app = buildApp();
      const res = await app.inject({
        method: 'GET',
        url: '/api/worktrees/wt-abc123/diff',
        headers: { authorization: `Bearer ${TOKEN}` },
      });

      expect(res.statusCode).toBe(200);
      expect(res.json().files).toEqual([]);
    });

    test('given unknown worktree, should return 404', async () => {
      mockedResolveWorktree.mockReturnValue(undefined);

      const app = buildApp();
      const res = await app.inject({
        method: 'GET',
        url: '/api/worktrees/wt-unknown/diff',
        headers: { authorization: `Bearer ${TOKEN}` },
      });

      expect(res.statusCode).toBe(404);
      expect(res.json()).toEqual({ error: 'Worktree not found: wt-unknown' });
    });

    test('should call git diff with correct range', async () => {
      mockedResolveWorktree.mockReturnValue(mockManifest.worktrees['wt-abc123']);
      mockedExeca.mockResolvedValue({ stdout: '' } as never);

      const app = buildApp();
      await app.inject({
        method: 'GET',
        url: '/api/worktrees/wt-abc123/diff',
        headers: { authorization: `Bearer ${TOKEN}` },
      });

      expect(mockedExeca).toHaveBeenCalledWith(
        'git',
        ['diff', '--numstat', 'main...ppg/feature-auth'],
        expect.objectContaining({ cwd: PROJECT_ROOT }),
      );
    });

    test('given binary files in diff, should treat dash counts as 0', async () => {
      mockedResolveWorktree.mockReturnValue(mockManifest.worktrees['wt-abc123']);
      mockedExeca.mockResolvedValue({
        stdout: '-\t-\timage.png',
      } as never);

      const app = buildApp();
      const res = await app.inject({
        method: 'GET',
        url: '/api/worktrees/wt-abc123/diff',
        headers: { authorization: `Bearer ${TOKEN}` },
      });

      expect(res.json().files).toEqual([
        { file: 'image.png', added: 0, removed: 0 },
      ]);
    });
  });
});
