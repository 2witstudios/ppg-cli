import { describe, test, expect, vi, beforeEach } from 'vitest';
import Fastify from 'fastify';
import type { FastifyInstance } from 'fastify';
import statusRoutes from './status.js';
import { makeWorktree, makeAgent } from '../../test-fixtures.js';
import type { Manifest } from '../../types/manifest.js';
import { NotInitializedError, ManifestLockError } from '../../lib/errors.js';

const PROJECT_ROOT = '/tmp/project';
const TOKEN = 'test-token-123';

const mockManifest: Manifest = {
  version: 1,
  projectRoot: PROJECT_ROOT,
  sessionName: 'ppg-test',
  agents: {},
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
  readManifest: vi.fn(),
  resolveWorktree: vi.fn(),
  updateManifest: vi.fn(),
}));

vi.mock('../../core/agent.js', () => ({
  refreshAllAgentStatuses: vi.fn((m: Manifest) => m),
}));

vi.mock('execa', () => ({
  execa: vi.fn(),
}));

import { readManifest, resolveWorktree, updateManifest } from '../../core/manifest.js';
import { refreshAllAgentStatuses } from '../../core/agent.js';
import { execa } from 'execa';

const mockedUpdateManifest = vi.mocked(updateManifest);
const mockedReadManifest = vi.mocked(readManifest);
const mockedResolveWorktree = vi.mocked(resolveWorktree);
const mockedRefreshAllAgentStatuses = vi.mocked(refreshAllAgentStatuses);
const mockedExeca = vi.mocked(execa);

function buildApp(): FastifyInstance {
  const app = Fastify();
  app.register(statusRoutes, { projectRoot: PROJECT_ROOT, bearerToken: TOKEN });
  return app;
}

function authHeaders() {
  return { authorization: `Bearer ${TOKEN}` };
}

describe('status routes', () => {
  beforeEach(() => {
    vi.clearAllMocks();

    mockedUpdateManifest.mockImplementation(async (_root, updater) => {
      return updater(structuredClone(mockManifest));
    });
    mockedReadManifest.mockResolvedValue(structuredClone(mockManifest));
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
        headers: authHeaders(),
      });
      expect(res.statusCode).toBe(200);
    });

    test('given failed auth, should not execute route handler', async () => {
      const app = buildApp();
      await app.inject({ method: 'GET', url: '/api/status' });
      expect(mockedUpdateManifest).not.toHaveBeenCalled();
    });
  });

  describe('GET /api/status', () => {
    test('should return full manifest with lifecycle', async () => {
      const app = buildApp();
      const res = await app.inject({
        method: 'GET',
        url: '/api/status',
        headers: authHeaders(),
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
        headers: authHeaders(),
      });

      expect(mockedRefreshAllAgentStatuses).toHaveBeenCalled();
    });

    test('given manifest lock error, should return 503', async () => {
      mockedUpdateManifest.mockRejectedValue(new ManifestLockError());

      const app = buildApp();
      const res = await app.inject({
        method: 'GET',
        url: '/api/status',
        headers: authHeaders(),
      });

      expect(res.statusCode).toBe(503);
      expect(res.json().code).toBe('MANIFEST_LOCK');
    });

    test('given not initialized error, should return 503', async () => {
      mockedUpdateManifest.mockRejectedValue(new NotInitializedError('/tmp/project'));

      const app = buildApp();
      const res = await app.inject({
        method: 'GET',
        url: '/api/status',
        headers: authHeaders(),
      });

      expect(res.statusCode).toBe(503);
      expect(res.json().code).toBe('NOT_INITIALIZED');
    });
  });

  describe('GET /api/worktrees/:id', () => {
    test('given valid worktree id, should return worktree detail', async () => {
      mockedResolveWorktree.mockReturnValue(mockManifest.worktrees['wt-abc123']);

      const app = buildApp();
      const res = await app.inject({
        method: 'GET',
        url: '/api/worktrees/wt-abc123',
        headers: authHeaders(),
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
        headers: authHeaders(),
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
        headers: authHeaders(),
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
        headers: authHeaders(),
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
        headers: authHeaders(),
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
        headers: authHeaders(),
      });

      expect(res.statusCode).toBe(404);
      expect(res.json()).toEqual({ error: 'Worktree not found: wt-unknown' });
    });

    test('given missing manifest file, should return 503', async () => {
      const enoentError = Object.assign(new Error('not found'), { code: 'ENOENT' });
      mockedReadManifest.mockRejectedValue(enoentError);

      const app = buildApp();
      const res = await app.inject({
        method: 'GET',
        url: '/api/worktrees/wt-abc123/diff',
        headers: authHeaders(),
      });

      expect(res.statusCode).toBe(503);
      expect(res.json().code).toBe('NOT_INITIALIZED');
    });

    test('should call git diff with correct range', async () => {
      mockedResolveWorktree.mockReturnValue(mockManifest.worktrees['wt-abc123']);
      mockedExeca.mockResolvedValue({ stdout: '' } as never);

      const app = buildApp();
      await app.inject({
        method: 'GET',
        url: '/api/worktrees/wt-abc123/diff',
        headers: authHeaders(),
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
        headers: authHeaders(),
      });

      expect(res.json().files).toEqual([
        { file: 'image.png', added: 0, removed: 0 },
      ]);
    });

    test('given git diff failure, should return 500', async () => {
      mockedResolveWorktree.mockReturnValue(mockManifest.worktrees['wt-abc123']);
      mockedExeca.mockRejectedValue(new Error('git diff failed'));

      const app = buildApp();
      const res = await app.inject({
        method: 'GET',
        url: '/api/worktrees/wt-abc123/diff',
        headers: authHeaders(),
      });

      expect(res.statusCode).toBe(500);
    });

    test('should use readManifest instead of updateManifest', async () => {
      mockedResolveWorktree.mockReturnValue(mockManifest.worktrees['wt-abc123']);
      mockedExeca.mockResolvedValue({ stdout: '' } as never);

      const app = buildApp();
      await app.inject({
        method: 'GET',
        url: '/api/worktrees/wt-abc123/diff',
        headers: authHeaders(),
      });

      expect(mockedReadManifest).toHaveBeenCalledWith(PROJECT_ROOT);
      expect(mockedUpdateManifest).not.toHaveBeenCalled();
    });
  });
});
