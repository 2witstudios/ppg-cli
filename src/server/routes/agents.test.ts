import { describe, test, expect, vi, beforeEach } from 'vitest';
import Fastify from 'fastify';
import { agentRoutes } from './agents.js';
import type { Manifest } from '../../types/manifest.js';
import { makeAgent, makeWorktree } from '../../test-fixtures.js';

// ---- Mocks ----

const mockAgent = makeAgent({ id: 'ag-test1234', tmuxTarget: 'ppg:1.0' });
const mockWorktree = makeWorktree({
  id: 'wt-abc123',
  agents: { 'ag-test1234': mockAgent },
});

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
  spawnAgent: vi.fn(),
}));

vi.mock('../../core/tmux.js', () => ({
  capturePane: vi.fn(),
  sendKeys: vi.fn(),
  sendLiteral: vi.fn(),
  sendRawKeys: vi.fn(),
  ensureSession: vi.fn(),
  createWindow: vi.fn(),
}));

vi.mock('../../core/config.js', () => ({
  loadConfig: vi.fn(),
  resolveAgentConfig: vi.fn(),
}));

vi.mock('../../core/template.js', () => ({
  renderTemplate: vi.fn((content: string) => content),
}));

vi.mock('../../lib/id.js', () => ({
  agentId: vi.fn(() => 'ag-new12345'),
  sessionId: vi.fn(() => 'session-uuid-123'),
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
import { killAgent, spawnAgent } from '../../core/agent.js';
import * as tmux from '../../core/tmux.js';
import { loadConfig, resolveAgentConfig } from '../../core/config.js';
import fs from 'node:fs/promises';

const PROJECT_ROOT = '/tmp/project';

async function buildApp() {
  const app = Fastify();
  await app.register(agentRoutes, { prefix: '/api', projectRoot: PROJECT_ROOT });
  return app;
}

beforeEach(() => {
  vi.clearAllMocks();
});

// ---------- GET /api/agents/:id/logs ----------

describe('GET /api/agents/:id/logs', () => {
  test('returns captured pane output with default 200 lines', async () => {
    const manifest = makeManifest();
    vi.mocked(requireManifest).mockResolvedValue(manifest);
    vi.mocked(findAgent).mockReturnValue({
      worktree: manifest.worktrees['wt-abc123'],
      agent: manifest.worktrees['wt-abc123'].agents['ag-test1234'],
    });
    vi.mocked(tmux.capturePane).mockResolvedValue('line1\nline2\nline3');

    const app = await buildApp();
    const res = await app.inject({ method: 'GET', url: '/api/agents/ag-test1234/logs' });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.agentId).toBe('ag-test1234');
    expect(body.output).toBe('line1\nline2\nline3');
    expect(body.lines).toBe(200);
    expect(tmux.capturePane).toHaveBeenCalledWith('ppg:1.0', 200);
  });

  test('respects custom lines parameter', async () => {
    const manifest = makeManifest();
    vi.mocked(requireManifest).mockResolvedValue(manifest);
    vi.mocked(findAgent).mockReturnValue({
      worktree: manifest.worktrees['wt-abc123'],
      agent: manifest.worktrees['wt-abc123'].agents['ag-test1234'],
    });
    vi.mocked(tmux.capturePane).mockResolvedValue('output');

    const app = await buildApp();
    const res = await app.inject({ method: 'GET', url: '/api/agents/ag-test1234/logs?lines=50' });

    expect(res.statusCode).toBe(200);
    expect(res.json().lines).toBe(50);
    expect(tmux.capturePane).toHaveBeenCalledWith('ppg:1.0', 50);
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
});

// ---------- POST /api/agents/:id/send ----------

describe('POST /api/agents/:id/send', () => {
  test('sends text with Enter by default', async () => {
    const manifest = makeManifest();
    vi.mocked(requireManifest).mockResolvedValue(manifest);
    vi.mocked(findAgent).mockReturnValue({
      worktree: manifest.worktrees['wt-abc123'],
      agent: manifest.worktrees['wt-abc123'].agents['ag-test1234'],
    });

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-test1234/send',
      payload: { text: 'hello' },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json().success).toBe(true);
    expect(res.json().mode).toBe('with-enter');
    expect(tmux.sendKeys).toHaveBeenCalledWith('ppg:1.0', 'hello');
  });

  test('sends literal text without Enter', async () => {
    const manifest = makeManifest();
    vi.mocked(requireManifest).mockResolvedValue(manifest);
    vi.mocked(findAgent).mockReturnValue({
      worktree: manifest.worktrees['wt-abc123'],
      agent: manifest.worktrees['wt-abc123'].agents['ag-test1234'],
    });

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-test1234/send',
      payload: { text: 'hello', mode: 'literal' },
    });

    expect(res.statusCode).toBe(200);
    expect(tmux.sendLiteral).toHaveBeenCalledWith('ppg:1.0', 'hello');
  });

  test('sends raw tmux keys', async () => {
    const manifest = makeManifest();
    vi.mocked(requireManifest).mockResolvedValue(manifest);
    vi.mocked(findAgent).mockReturnValue({
      worktree: manifest.worktrees['wt-abc123'],
      agent: manifest.worktrees['wt-abc123'].agents['ag-test1234'],
    });

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-test1234/send',
      payload: { text: 'C-c', mode: 'raw' },
    });

    expect(res.statusCode).toBe(200);
    expect(tmux.sendRawKeys).toHaveBeenCalledWith('ppg:1.0', 'C-c');
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

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-test1234/kill',
    });

    expect(res.statusCode).toBe(200);
    expect(res.json().message).toMatch(/already gone/);
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
  test('restarts a running agent with original prompt', async () => {
    const manifest = makeManifest();
    vi.mocked(requireManifest).mockResolvedValue(manifest);
    vi.mocked(findAgent).mockReturnValue({
      worktree: manifest.worktrees['wt-abc123'],
      agent: manifest.worktrees['wt-abc123'].agents['ag-test1234'],
    });
    vi.mocked(killAgent).mockResolvedValue(undefined);
    vi.mocked(fs.readFile).mockResolvedValue('original prompt');
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
    vi.mocked(tmux.ensureSession).mockResolvedValue(undefined);
    vi.mocked(tmux.createWindow).mockResolvedValue('ppg:2');
    vi.mocked(spawnAgent).mockResolvedValue(makeAgent({
      id: 'ag-new12345',
      tmuxTarget: 'ppg:2',
    }));
    vi.mocked(updateManifest).mockImplementation(async (_root, updater) => {
      const m = makeManifest();
      return updater(m);
    });

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
    expect(killAgent).toHaveBeenCalled();
    expect(spawnAgent).toHaveBeenCalled();
  });

  test('uses prompt override when provided', async () => {
    const manifest = makeManifest();
    vi.mocked(requireManifest).mockResolvedValue(manifest);
    vi.mocked(findAgent).mockReturnValue({
      worktree: manifest.worktrees['wt-abc123'],
      agent: manifest.worktrees['wt-abc123'].agents['ag-test1234'],
    });
    vi.mocked(killAgent).mockResolvedValue(undefined);
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
    vi.mocked(tmux.ensureSession).mockResolvedValue(undefined);
    vi.mocked(tmux.createWindow).mockResolvedValue('ppg:2');
    vi.mocked(spawnAgent).mockResolvedValue(makeAgent({ id: 'ag-new12345', tmuxTarget: 'ppg:2' }));
    vi.mocked(updateManifest).mockImplementation(async (_root, updater) => {
      const m = makeManifest();
      return updater(m);
    });

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/agents/ag-test1234/restart',
      payload: { prompt: 'new task' },
    });

    expect(res.statusCode).toBe(200);
    // Should NOT read the old prompt file
    expect(fs.readFile).not.toHaveBeenCalled();
    // spawnAgent should receive the override prompt
    expect(spawnAgent).toHaveBeenCalledWith(
      expect.objectContaining({ prompt: 'new task' }),
    );
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
