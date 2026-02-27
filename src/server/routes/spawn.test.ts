import { describe, test, expect, vi, beforeEach } from 'vitest';
import Fastify from 'fastify';
import type { FastifyInstance } from 'fastify';
import spawnRoute from './spawn.js';
import type { SpawnRequestBody, SpawnResponseBody } from './spawn.js';

// ─── Mocks ────────────────────────────────────────────────────────────────────

vi.mock('../../core/worktree.js', () => ({
  getRepoRoot: vi.fn().mockResolvedValue('/fake/project'),
  getCurrentBranch: vi.fn().mockResolvedValue('main'),
  createWorktree: vi.fn().mockResolvedValue('/fake/project/.worktrees/wt-abc123'),
}));

vi.mock('../../core/config.js', () => ({
  loadConfig: vi.fn().mockResolvedValue({
    sessionName: 'ppg',
    defaultAgent: 'claude',
    agents: {
      claude: { name: 'claude', command: 'claude --dangerously-skip-permissions', interactive: true },
      codex: { name: 'codex', command: 'codex --yolo', interactive: true },
    },
    envFiles: ['.env'],
    symlinkNodeModules: true,
  }),
  resolveAgentConfig: vi.fn().mockReturnValue({
    name: 'claude',
    command: 'claude --dangerously-skip-permissions',
    interactive: true,
  }),
}));

vi.mock('../../core/manifest.js', () => ({
  readManifest: vi.fn().mockResolvedValue({
    version: 1,
    projectRoot: '/fake/project',
    sessionName: 'ppg-test',
    worktrees: {},
    createdAt: '2025-01-01T00:00:00.000Z',
    updatedAt: '2025-01-01T00:00:00.000Z',
  }),
  updateManifest: vi.fn().mockImplementation(async (_root, updater) => {
    const manifest = {
      version: 1,
      projectRoot: '/fake/project',
      sessionName: 'ppg-test',
      worktrees: {},
      createdAt: '2025-01-01T00:00:00.000Z',
      updatedAt: '2025-01-01T00:00:00.000Z',
    };
    return updater(manifest);
  }),
}));

vi.mock('../../core/env.js', () => ({
  setupWorktreeEnv: vi.fn().mockResolvedValue(undefined),
}));

vi.mock('../../core/tmux.js', () => ({
  ensureSession: vi.fn().mockResolvedValue(undefined),
  createWindow: vi.fn().mockResolvedValue('ppg-test:my-task'),
}));

vi.mock('../../core/agent.js', () => ({
  spawnAgent: vi.fn().mockImplementation(async (opts) => ({
    id: opts.agentId,
    name: 'claude',
    agentType: 'claude',
    status: 'running',
    tmuxTarget: opts.tmuxTarget,
    prompt: opts.prompt.slice(0, 500),
    startedAt: '2025-01-01T00:00:00.000Z',
    sessionId: opts.sessionId,
  })),
}));

vi.mock('../../core/template.js', () => ({
  loadTemplate: vi.fn().mockResolvedValue('Template: {{TASK_NAME}} in {{BRANCH}}'),
  renderTemplate: vi.fn().mockImplementation((content: string, ctx: Record<string, string | undefined>) => {
    return content.replace(/\{\{(\w+)\}\}/g, (_match: string, key: string) => {
      return ctx[key] ?? `{{${key}}}`;
    });
  }),
}));

vi.mock('../../lib/id.js', () => {
  let agentCounter = 0;
  return {
    worktreeId: vi.fn().mockReturnValue('wt-abc123'),
    agentId: vi.fn().mockImplementation(() => `ag-agent${String(++agentCounter).padStart(3, '0')}`),
    sessionId: vi.fn().mockReturnValue('sess-uuid-001'),
  };
});

vi.mock('../../lib/name.js', () => ({
  normalizeName: vi.fn().mockImplementation((raw: string) => raw.toLowerCase()),
}));

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify();
  await app.register(spawnRoute);
  return app;
}

function postSpawn(app: FastifyInstance, body: Partial<SpawnRequestBody>) {
  return app.inject({
    method: 'POST',
    url: '/api/spawn',
    payload: body,
  });
}

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('POST /api/spawn', () => {
  let app: FastifyInstance;

  beforeEach(async () => {
    vi.clearAllMocks();
    // Reset agent counter by re-importing
    const idMod = await import('../../lib/id.js');
    let counter = 0;
    vi.mocked(idMod.agentId).mockImplementation(() => `ag-agent${String(++counter).padStart(3, '0')}`);

    app = await buildApp();
  });

  test('given valid name and prompt, should spawn worktree with 1 agent', async () => {
    const res = await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix the bug',
    });

    expect(res.statusCode).toBe(201);
    const body = res.json<SpawnResponseBody>();
    expect(body.worktreeId).toBe('wt-abc123');
    expect(body.name).toBe('my-task');
    expect(body.branch).toBe('ppg/my-task');
    expect(body.agents).toHaveLength(1);
    expect(body.agents[0].id).toMatch(/^ag-/);
    expect(body.agents[0].tmuxTarget).toBe('ppg-test:my-task');
    expect(body.agents[0].sessionId).toBe('sess-uuid-001');
  });

  test('given count > 1, should spawn multiple agents', async () => {
    const { createWindow } = await import('../../core/tmux.js');
    vi.mocked(createWindow)
      .mockResolvedValueOnce('ppg-test:my-task')
      .mockResolvedValueOnce('ppg-test:my-task-1')
      .mockResolvedValueOnce('ppg-test:my-task-2');

    const res = await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix the bug',
      count: 3,
    });

    expect(res.statusCode).toBe(201);
    const body = res.json<SpawnResponseBody>();
    expect(body.agents).toHaveLength(3);
  });

  test('given template name, should load and render template', async () => {
    const { loadTemplate } = await import('../../core/template.js');
    const { spawnAgent } = await import('../../core/agent.js');

    const res = await postSpawn(app, {
      name: 'my-task',
      template: 'review',
    });

    expect(res.statusCode).toBe(201);
    expect(vi.mocked(loadTemplate)).toHaveBeenCalledWith('/fake/project', 'review');
    // renderTemplate is called with the loaded template content
    const spawnCall = vi.mocked(spawnAgent).mock.calls[0][0];
    expect(spawnCall.prompt).toContain('my-task');
    expect(spawnCall.prompt).toContain('ppg/my-task');
  });

  test('given template with vars, should substitute variables', async () => {
    const { loadTemplate, renderTemplate } = await import('../../core/template.js');
    vi.mocked(loadTemplate).mockResolvedValueOnce('Fix {{ISSUE}} on {{REPO}}');

    const res = await postSpawn(app, {
      name: 'my-task',
      template: 'fix-issue',
      vars: { ISSUE: '#42', REPO: 'ppg-cli' },
    });

    expect(res.statusCode).toBe(201);
    // renderTemplate receives user vars merged into context
    const renderCall = vi.mocked(renderTemplate).mock.calls[0];
    const ctx = renderCall[1];
    expect(ctx.ISSUE).toBe('#42');
    expect(ctx.REPO).toBe('ppg-cli');
  });

  test('given agent type, should resolve that agent config', async () => {
    const { resolveAgentConfig } = await import('../../core/config.js');

    await postSpawn(app, {
      name: 'my-task',
      prompt: 'Do the thing',
      agent: 'codex',
    });

    expect(vi.mocked(resolveAgentConfig)).toHaveBeenCalledWith(
      expect.objectContaining({ defaultAgent: 'claude' }),
      'codex',
    );
  });

  test('given base branch, should use it instead of current branch', async () => {
    const { createWorktree } = await import('../../core/worktree.js');

    await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix it',
      base: 'develop',
    });

    expect(vi.mocked(createWorktree)).toHaveBeenCalledWith(
      '/fake/project',
      'wt-abc123',
      { branch: 'ppg/my-task', base: 'develop' },
    );
  });

  test('given no base, should default to current branch', async () => {
    const { createWorktree } = await import('../../core/worktree.js');

    await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix it',
    });

    expect(vi.mocked(createWorktree)).toHaveBeenCalledWith(
      '/fake/project',
      'wt-abc123',
      { branch: 'ppg/my-task', base: 'main' },
    );
  });

  // ─── Validation ─────────────────────────────────────────────────────────────

  test('given missing name, should return 400', async () => {
    const res = await postSpawn(app, {
      prompt: 'Fix the bug',
    });

    expect(res.statusCode).toBe(400);
    const body = res.json<{ message: string }>();
    expect(body.message).toMatch(/name/i);
  });

  test('given empty name, should return 400', async () => {
    const res = await postSpawn(app, {
      name: '',
      prompt: 'Fix the bug',
    });

    expect(res.statusCode).toBe(400);
  });

  test('given neither prompt nor template, should return 500 with INVALID_ARGS', async () => {
    const res = await postSpawn(app, {
      name: 'my-task',
    });

    // PpgError with INVALID_ARGS is thrown — Fastify returns 500 without a custom error handler
    expect(res.statusCode).toBe(500);
    const body = res.json<{ message: string }>();
    expect(body.message).toMatch(/prompt.*template/i);
  });

  test('given count below 1, should return 400', async () => {
    const res = await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix the bug',
      count: 0,
    });

    expect(res.statusCode).toBe(400);
  });

  test('given count above 20, should return 400', async () => {
    const res = await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix the bug',
      count: 21,
    });

    expect(res.statusCode).toBe(400);
  });

  test('given non-integer count, should return 400', async () => {
    const res = await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix the bug',
      count: 1.5,
    });

    expect(res.statusCode).toBe(400);
  });

  test('given unknown property, should strip it and succeed', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/spawn',
      payload: {
        name: 'my-task',
        prompt: 'Fix the bug',
        unknown: 'value',
      },
    });

    // Fastify with additionalProperties:false removes unknown props by default
    expect(res.statusCode).toBe(201);
  });

  // ─── Manifest Updates ───────────────────────────────────────────────────────

  test('should register worktree in manifest before spawning agents', async () => {
    const { updateManifest } = await import('../../core/manifest.js');

    await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix the bug',
    });

    // First call registers worktree skeleton, second adds the agent
    expect(vi.mocked(updateManifest)).toHaveBeenCalledTimes(2);
  });

  test('should setup worktree env', async () => {
    const { setupWorktreeEnv } = await import('../../core/env.js');

    await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix the bug',
    });

    expect(vi.mocked(setupWorktreeEnv)).toHaveBeenCalledWith(
      '/fake/project',
      '/fake/project/.worktrees/wt-abc123',
      expect.objectContaining({ sessionName: 'ppg' }),
    );
  });

  test('should ensure tmux session exists', async () => {
    const { ensureSession } = await import('../../core/tmux.js');

    await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix the bug',
    });

    expect(vi.mocked(ensureSession)).toHaveBeenCalledWith('ppg-test');
  });
});
