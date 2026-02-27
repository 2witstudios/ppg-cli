import { describe, test, expect, vi, beforeEach } from 'vitest';
import Fastify from 'fastify';
import { agentRoutes } from './agents.js';
import type { Manifest } from '../../types/manifest.js';
import { makeAgent, makeWorktree } from '../../test-fixtures.js';

// ---- Mocks ----

function makeManifest(overrides?: Partial<Manifest>): Manifest {
  return {
    version: 1,
    projectRoot: '/tmp/project',
    sessionName: 'ppg',
    worktrees: { 'wt-abc123': makeWorktree({ agents: { 'ag-test1234': makeAgent() } }) },
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  };
}

vi.mock('../../core/manifest.js', () => ({
  requireManifest: vi.fn(),
  findAgent: vi.fn(),
  updateManifest: vi.fn(),
}));

vi.mock('../../core/agent.js', () => ({
  killAgent: vi.fn(),
  checkAgentStatus: vi.fn(),
  restartAgent: vi.fn(),
}));

const mockCapturePane = vi.fn();
const mockSendKeys = vi.fn();
const mockSendLiteral = vi.fn();
const mockSendRawKeys = vi.fn();
vi.mock('../../core/backend.js', () => ({
  getBackend: () => ({
    capturePane: mockCapturePane,
    sendKeys: mockSendKeys,
    sendLiteral: mockSendLiteral,
    sendRawKeys: mockSendRawKeys,
  }),
}));

vi.mock('../../core/config.js', () => ({
  loadConfig: vi.fn(),
  resolveAgentConfig: vi.fn(),
}));

vi.mock('node:fs/promises', async () => {
  const actual = await vi.importActual<typeof import('node:fs/promises')>('node:fs/promises');
  return {
    ...actual,
    default: {
      ...actual,
      readFile: vi.fn(),
    },
  };
});

import { requireManifest, findAgent, updateManifest } from '../../core/manifest.js';
import { killAgent, checkAgentStatus, restartAgent } from '../../core/agent.js';
import { loadConfig, resolveAgentConfig } from '../../core/config.js';
import fs from 'node:fs/promises';

const PROJECT_ROOT = '/tmp/project';

async function buildApp() {
  const app = Fastify();
  await app.register(agentRoutes, { prefix: '/api', projectRoot: PROJECT_ROOT });
  return app;
}

function setupAgentMocks(manifest?: Manifest) {
  const m = manifest ?? makeManifest();
  vi.mocked(requireManifest).mockResolvedValue(m);
  vi.mocked(findAgent).mockReturnValue({
    worktree: m.worktrees['wt-abc123'],
    agent: m.worktrees['wt-abc123'].agents['ag-test1234'],
  });
  return m;
}

beforeEach(() => {
  vi.clearAllMocks();
});

// ---------- GET /api/agents/:id/logs ----------

describe('GET /api/agents/:id/logs', () => {
  test('returns captured pane output with default 200 lines', async () => {
    setupAgentMocks();
    vi.mocked(mockCapturePane).mockResolvedValue('line1\nline2\nline3');

    const app = await buildApp();
    const res = await app.inject({ method: 'GET', url: '/api/agents/ag-test1234/logs' });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.agentId).toBe('ag-test1234');
    expect(body.output).toBe('line1\nline2\nline3');
    expect(body.lines).toBe(200);
    expect(mockCapturePane).toHaveBeenCalledWith('ppg:1.0', 200);
  });

  test('respects custom lines parameter', async () => {
    setupAgentMocks();
    vi.mocked(mockCapturePane).mockResolvedValue('output');

    const app = await buildApp();
    const res = await app.inject({ method: 'GET', url: '/api/agents/ag-test1234/logs?lines=50' });

    expect(res.statusCode).toBe(200);
    expect(res.json().lines).toBe(50);
    expect(mockCapturePane).toHaveBeenCalledWith('ppg:1.0', 50);
  });

  test('caps lines at 10000', async () => {
    setupAgentMocks();
    vi.mocked(mockCapturePane).mockResolvedValue('output');

    const app = await buildApp();
    const res = await app.inject({ method: 'GET', url: '/api/agents/ag-test1234/logs?lines=999999' });

    expect(res.statusCode).toBe(200);
    expect(res.json().lines).toBe(10000);
    expect(mockCapturePane).toHaveBeenCalledWith('ppg:1.0', 10000);
  });

  test('returns 400 for invalid lines', async () => {
    const app = await buildApp();
    const res = await app.inject({ method: 'GET', url: '/api/agents/ag-test1234/logs?lines=abc' });

    expect(res.statusCode).toBe(400);
    expect(res.json().code).toBe('INVALID_ARGS');
  });

  test('returns 404 for unknown agent', async () => {
    vi.mocked(requireManifest).mockResolvedValue(makeManifest());
    vi.mocked(findAgent).mockReturnValue(undefined);

    const app = await buildApp();
    const res = await app.inject({ method: 'GET', url: '/api/agents/ag-unknown/logs' });

    expect(res.statusCode).toBe(404);
    expect(res.json().code).toBe('AGENT_NOT_FOUND');
  });

  test('returns 410 when pane no longer exists', async () => {
    setupAgentMocks();
    vi.mocked(mockCapturePane).mockRejectedValue(new Error('pane not found'));

    const app = await buildApp();
    const res = await app.inject({ method: 'GET', url: '/api/agents/ag-test1234/logs' });

    expect(res.statusCode).toBe(410);
    expect(res.json().code).toBe('PANE_NOT_FOUND');
  });
});

// ---------- POST /api/agents/:id/send ----------

describe('POST /api/agents/:id/send', () => {
  test('sends text with Enter by default', async () => {
    setupAgentMocks();

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-test1234/send',
      payload: { text: 'hello' },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json().success).toBe(true);
    expect(res.json().mode).toBe('with-enter');
    expect(mockSendKeys).toHaveBeenCalledWith('ppg:1.0', 'hello');
  });

  test('sends literal text without Enter', async () => {
    setupAgentMocks();

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-test1234/send',
      payload: { text: 'hello', mode: 'literal' },
    });

    expect(res.statusCode).toBe(200);
    expect(mockSendLiteral).toHaveBeenCalledWith('ppg:1.0', 'hello');
  });

  test('sends raw tmux keys', async () => {
    setupAgentMocks();

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-test1234/send',
      payload: { text: 'C-c', mode: 'raw' },
    });

    expect(res.statusCode).toBe(200);
    expect(mockSendRawKeys).toHaveBeenCalledWith('ppg:1.0', 'C-c');
  });

  test('rejects invalid mode', async () => {
    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-test1234/send',
      payload: { text: 'hello', mode: 'invalid' },
    });

    expect(res.statusCode).toBe(400);
  });

  test('rejects missing text field', async () => {
    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-test1234/send',
      payload: {},
    });

    expect(res.statusCode).toBe(400);
  });

  test('returns 404 for unknown agent', async () => {
    vi.mocked(requireManifest).mockResolvedValue(makeManifest());
    vi.mocked(findAgent).mockReturnValue(undefined);

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-unknown/send',
      payload: { text: 'hello' },
    });

    expect(res.statusCode).toBe(404);
  });
});

// ---------- POST /api/agents/:id/kill ----------

describe('POST /api/agents/:id/kill', () => {
  test('kills a running agent', async () => {
    const manifest = makeManifest();
    vi.mocked(requireManifest).mockResolvedValue(manifest);
    vi.mocked(findAgent)
      .mockReturnValueOnce({
        worktree: manifest.worktrees['wt-abc123'],
        agent: manifest.worktrees['wt-abc123'].agents['ag-test1234'],
      })
      .mockReturnValueOnce({
        worktree: manifest.worktrees['wt-abc123'],
        agent: manifest.worktrees['wt-abc123'].agents['ag-test1234'],
      });
    vi.mocked(checkAgentStatus).mockResolvedValue({ status: 'running' });
    vi.mocked(killAgent).mockResolvedValue(undefined);
    vi.mocked(updateManifest).mockImplementation(async (_root, updater) => {
      const m = makeManifest();
      return updater(m);
    });

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-test1234/kill',
    });

    expect(res.statusCode).toBe(200);
    expect(res.json().success).toBe(true);
    expect(res.json().killed).toBe(true);
    expect(checkAgentStatus).toHaveBeenCalled();
    expect(killAgent).toHaveBeenCalled();
    expect(updateManifest).toHaveBeenCalled();
  });

  test('returns success without killing already-stopped agent', async () => {
    const stoppedAgent = makeAgent({ status: 'gone' });
    const manifest = makeManifest({
      worktrees: { 'wt-abc123': makeWorktree({ agents: { 'ag-test1234': stoppedAgent } }) },
    });
    vi.mocked(requireManifest).mockResolvedValue(manifest);
    vi.mocked(findAgent).mockReturnValue({
      worktree: manifest.worktrees['wt-abc123'],
      agent: stoppedAgent,
    });
    vi.mocked(checkAgentStatus).mockResolvedValue({ status: 'gone' });

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-test1234/kill',
    });

    expect(res.statusCode).toBe(200);
    expect(res.json().message).toMatch(/already gone/);
    expect(killAgent).not.toHaveBeenCalled();
  });

  test('uses live tmux status instead of stale manifest status', async () => {
    // Agent shows "running" in manifest but tmux says "idle"
    const agent = makeAgent({ status: 'running' });
    const manifest = makeManifest({
      worktrees: { 'wt-abc123': makeWorktree({ agents: { 'ag-test1234': agent } }) },
    });
    vi.mocked(requireManifest).mockResolvedValue(manifest);
    vi.mocked(findAgent).mockReturnValue({
      worktree: manifest.worktrees['wt-abc123'],
      agent,
    });
    vi.mocked(checkAgentStatus).mockResolvedValue({ status: 'idle' });

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-test1234/kill',
    });

    expect(res.statusCode).toBe(200);
    expect(res.json().message).toMatch(/already idle/);
    expect(killAgent).not.toHaveBeenCalled();
  });

  test('returns 404 for unknown agent', async () => {
    vi.mocked(requireManifest).mockResolvedValue(makeManifest());
    vi.mocked(findAgent).mockReturnValue(undefined);

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-unknown/kill',
    });

    expect(res.statusCode).toBe(404);
  });
});

// ---------- POST /api/agents/:id/restart ----------

describe('POST /api/agents/:id/restart', () => {
  function setupRestartMocks() {
    const manifest = makeManifest();
    vi.mocked(requireManifest).mockResolvedValue(manifest);
    vi.mocked(findAgent).mockReturnValue({
      worktree: manifest.worktrees['wt-abc123'],
      agent: manifest.worktrees['wt-abc123'].agents['ag-test1234'],
    });
    vi.mocked(loadConfig).mockResolvedValue({
      sessionName: 'ppg',
      defaultAgent: 'claude',
      agents: { claude: { name: 'claude', command: 'claude', interactive: true } },
      envFiles: [],
      symlinkNodeModules: true,
    });
    vi.mocked(resolveAgentConfig).mockReturnValue({
      name: 'claude',
      command: 'claude',
      interactive: true,
    });
    vi.mocked(restartAgent).mockResolvedValue({
      oldAgentId: 'ag-test1234',
      newAgentId: 'ag-new12345',
      tmuxTarget: 'ppg:2',
      sessionId: 'session-uuid-123',
      worktreeId: 'wt-abc123',
      worktreeName: 'feature-auth',
      branch: 'ppg/feature-auth',
      path: '/tmp/project/.worktrees/wt-abc123',
    });
    return manifest;
  }

  test('restarts a running agent with original prompt', async () => {
    setupRestartMocks();
    vi.mocked(fs.readFile).mockResolvedValue('original prompt');

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-test1234/restart',
      payload: {},
    });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.success).toBe(true);
    expect(body.oldAgentId).toBe('ag-test1234');
    expect(body.newAgent.id).toBe('ag-new12345');
    expect(restartAgent).toHaveBeenCalled();
  });

  test('uses prompt override when provided', async () => {
    setupRestartMocks();

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-test1234/restart',
      payload: { prompt: 'new task' },
    });

    expect(res.statusCode).toBe(200);
    expect(fs.readFile).not.toHaveBeenCalled();
    expect(restartAgent).toHaveBeenCalledWith(
      expect.objectContaining({ promptText: 'new task' }),
    );
  });

  test('skips kill for non-running agent', async () => {
    const idleAgent = makeAgent({ status: 'idle' });
    const manifest = makeManifest({
      worktrees: { 'wt-abc123': makeWorktree({ agents: { 'ag-test1234': idleAgent } }) },
    });
    vi.mocked(requireManifest).mockResolvedValue(manifest);
    vi.mocked(findAgent).mockReturnValue({
      worktree: manifest.worktrees['wt-abc123'],
      agent: idleAgent,
    });
    vi.mocked(loadConfig).mockResolvedValue({
      sessionName: 'ppg',
      defaultAgent: 'claude',
      agents: { claude: { name: 'claude', command: 'claude', interactive: true } },
      envFiles: [],
      symlinkNodeModules: true,
    });
    vi.mocked(resolveAgentConfig).mockReturnValue({
      name: 'claude',
      command: 'claude',
      interactive: true,
    });
    vi.mocked(fs.readFile).mockResolvedValue('original prompt');
    vi.mocked(restartAgent).mockResolvedValue({
      oldAgentId: 'ag-test1234',
      newAgentId: 'ag-new12345',
      tmuxTarget: 'ppg:2',
      sessionId: 'session-uuid-123',
      worktreeId: 'wt-abc123',
      worktreeName: 'feature-auth',
      branch: 'ppg/feature-auth',
      path: '/tmp/project/.worktrees/wt-abc123',
    });

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-test1234/restart',
      payload: {},
    });

    expect(res.statusCode).toBe(200);
    // restartAgent handles the kill-or-skip internally
    expect(restartAgent).toHaveBeenCalledWith(
      expect.objectContaining({ oldAgent: expect.objectContaining({ status: 'idle' }) }),
    );
  });

  test('returns 400 when prompt file missing and no override', async () => {
    const manifest = makeManifest();
    vi.mocked(requireManifest).mockResolvedValue(manifest);
    vi.mocked(findAgent).mockReturnValue({
      worktree: manifest.worktrees['wt-abc123'],
      agent: manifest.worktrees['wt-abc123'].agents['ag-test1234'],
    });
    vi.mocked(loadConfig).mockResolvedValue({
      sessionName: 'ppg',
      defaultAgent: 'claude',
      agents: { claude: { name: 'claude', command: 'claude', interactive: true } },
      envFiles: [],
      symlinkNodeModules: true,
    });
    vi.mocked(fs.readFile).mockRejectedValue(new Error('ENOENT'));

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-test1234/restart',
      payload: {},
    });

    expect(res.statusCode).toBe(400);
    expect(res.json().code).toBe('PROMPT_NOT_FOUND');
  });

  test('returns 404 for unknown agent', async () => {
    vi.mocked(requireManifest).mockResolvedValue(makeManifest());
    vi.mocked(findAgent).mockReturnValue(undefined);

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-unknown/restart',
      payload: {},
    });

    expect(res.statusCode).toBe(404);
  });
});
