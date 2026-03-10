import { describe, test, expect, vi, beforeEach } from 'vitest';
import Fastify from 'fastify';
import type { FastifyInstance } from 'fastify';
import spawnRoute from './spawn.js';
import type { SpawnRequestBody, SpawnResponseBody } from './spawn.js';

// ─── Mocks ────────────────────────────────────────────────────────────────────

vi.mock('../../core/spawn.js', () => ({
  spawnNewWorktree: vi.fn().mockResolvedValue({
    worktreeId: 'wt-abc123',
    name: 'my-task',
    branch: 'ppg/my-task',
    path: '/fake/project/.worktrees/wt-abc123',
    tmuxWindow: 'ppg-test:my-task',
    agents: [
      {
        id: 'ag-agent001',
        name: 'claude',
        agentType: 'claude',
        status: 'running',
        tmuxTarget: 'ppg-test:my-task',
        prompt: 'Fix the bug',
        startedAt: '2025-01-01T00:00:00.000Z',
        sessionId: 'sess-uuid-001',
      },
    ],
  }),
  resolvePromptText: vi.fn().mockResolvedValue('Fix the bug'),
}));

// ─── Helpers ──────────────────────────────────────────────────────────────────

const PROJECT_ROOT = '/fake/project';

async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify();
  await app.register(spawnRoute, { projectRoot: PROJECT_ROOT });
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
    app = await buildApp();
  });

  // ─── Happy Path ─────────────────────────────────────────────────────────────

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
    expect(body.agents[0].id).toBe('ag-agent001');
    expect(body.agents[0].tmuxTarget).toBe('ppg-test:my-task');
    expect(body.agents[0].sessionId).toBe('sess-uuid-001');
  });

  test('given all options, should pass them to spawnNewWorktree', async () => {
    const { spawnNewWorktree } = await import('../../core/spawn.js');

    await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix the bug',
      agent: 'codex',
      base: 'develop',
      count: 3,
      vars: { ISSUE: '42' },
    });

    expect(vi.mocked(spawnNewWorktree)).toHaveBeenCalledWith({
      projectRoot: PROJECT_ROOT,
      name: 'my-task',
      promptText: 'Fix the bug',
      userVars: { ISSUE: '42' },
      agentName: 'codex',
      baseBranch: 'develop',
      count: 3,
    });
  });

  test('given template name, should resolve prompt via resolvePromptText', async () => {
    const { resolvePromptText } = await import('../../core/spawn.js');

    await postSpawn(app, {
      name: 'my-task',
      template: 'review',
    });

    expect(vi.mocked(resolvePromptText)).toHaveBeenCalledWith(
      { prompt: undefined, template: 'review' },
      PROJECT_ROOT,
    );
  });

  test('given prompt and template both provided, should use prompt (prompt wins)', async () => {
    const { resolvePromptText } = await import('../../core/spawn.js');

    await postSpawn(app, {
      name: 'my-task',
      prompt: 'Inline prompt',
      template: 'review',
    });

    // resolvePromptText receives both — its implementation short-circuits on prompt
    expect(vi.mocked(resolvePromptText)).toHaveBeenCalledWith(
      expect.objectContaining({ prompt: 'Inline prompt', template: 'review' }),
      PROJECT_ROOT,
    );
  });

  test('given no vars, should pass undefined userVars', async () => {
    const { spawnNewWorktree } = await import('../../core/spawn.js');

    await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix it',
    });

    expect(vi.mocked(spawnNewWorktree)).toHaveBeenCalledWith(
      expect.objectContaining({ userVars: undefined }),
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

  // ─── Input Sanitization ─────────────────────────────────────────────────────

  test('given vars with shell metacharacters in value, should return 400 INVALID_ARGS', async () => {
    const res = await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix the bug',
      vars: { ISSUE: '$(whoami)' },
    });

    expect(res.statusCode).toBe(400);
    const body = res.json<{ message: string; code: string }>();
    expect(body.message).toMatch(/shell metacharacters/i);
    expect(body.code).toBe('INVALID_ARGS');
  });

  test('given vars with shell metacharacters in key, should return 400 INVALID_ARGS', async () => {
    const res = await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix the bug',
      vars: { 'KEY;rm': 'value' },
    });

    expect(res.statusCode).toBe(400);
    const body = res.json<{ message: string; code: string }>();
    expect(body.message).toMatch(/shell metacharacters/i);
    expect(body.code).toBe('INVALID_ARGS');
  });

  test('given vars with backtick in value, should reject', async () => {
    const res = await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix the bug',
      vars: { CMD: '`whoami`' },
    });

    expect(res.statusCode).toBe(400);
    const body = res.json<{ message: string; code: string }>();
    expect(body.message).toMatch(/shell metacharacters/i);
    expect(body.code).toBe('INVALID_ARGS');
  });

  test('given safe vars, should pass through', async () => {
    const { spawnNewWorktree } = await import('../../core/spawn.js');

    const res = await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix the bug',
      vars: { ISSUE: '42', REPO: 'ppg-cli', TAG: 'v1.0.0' },
    });

    expect(res.statusCode).toBe(201);
    expect(vi.mocked(spawnNewWorktree)).toHaveBeenCalledWith(
      expect.objectContaining({
        userVars: { ISSUE: '42', REPO: 'ppg-cli', TAG: 'v1.0.0' },
      }),
    );
  });

  // ─── Error Paths ────────────────────────────────────────────────────────────

  test('given neither prompt nor template, should return 400 with INVALID_ARGS', async () => {
    const { resolvePromptText } = await import('../../core/spawn.js');
    const { PpgError } = await import('../../lib/errors.js');
    vi.mocked(resolvePromptText).mockRejectedValueOnce(
      new PpgError('Either "prompt" or "template" is required', 'INVALID_ARGS'),
    );

    const res = await postSpawn(app, {
      name: 'my-task',
    });

    expect(res.statusCode).toBe(400);
    const body = res.json<{ message: string; code: string }>();
    expect(body.message).toMatch(/prompt.*template/i);
    expect(body.code).toBe('INVALID_ARGS');
  });

  test('given unknown agent type, should propagate error', async () => {
    const { spawnNewWorktree } = await import('../../core/spawn.js');
    vi.mocked(spawnNewWorktree).mockRejectedValueOnce(
      new Error('Unknown agent type: gpt. Available: claude, codex'),
    );

    const res = await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix it',
      agent: 'gpt',
    });

    expect(res.statusCode).toBe(500);
    const body = res.json<{ message: string }>();
    expect(body.message).toMatch(/Unknown agent type/);
  });

  test('given template not found, should propagate error', async () => {
    const { resolvePromptText } = await import('../../core/spawn.js');
    vi.mocked(resolvePromptText).mockRejectedValueOnce(
      new Error("ENOENT: no such file or directory, open '.ppg/templates/nonexistent.md'"),
    );

    const res = await postSpawn(app, {
      name: 'my-task',
      template: 'nonexistent',
    });

    expect(res.statusCode).toBe(500);
  });

  test('given not initialized error, should return 409', async () => {
    const { spawnNewWorktree } = await import('../../core/spawn.js');
    const { PpgError } = await import('../../lib/errors.js');
    vi.mocked(spawnNewWorktree).mockRejectedValueOnce(
      new PpgError('Point Guard not initialized in /fake/project', 'NOT_INITIALIZED'),
    );

    const res = await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix it',
    });

    expect(res.statusCode).toBe(409);
    const body = res.json<{ message: string; code: string }>();
    expect(body.message).toMatch(/not initialized/i);
    expect(body.code).toBe('NOT_INITIALIZED');
  });

  test('given tmux not available, should propagate TmuxNotFoundError', async () => {
    const { spawnNewWorktree } = await import('../../core/spawn.js');
    const { PpgError } = await import('../../lib/errors.js');
    vi.mocked(spawnNewWorktree).mockRejectedValueOnce(
      new PpgError('tmux is not installed or not in PATH', 'TMUX_NOT_FOUND'),
    );

    const res = await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix it',
    });

    expect(res.statusCode).toBe(500);
    const body = res.json<{ message: string }>();
    expect(body.message).toMatch(/tmux/i);
  });

  // ─── projectRoot Injection ──────────────────────────────────────────────────

  test('should use injected projectRoot, not process.cwd()', async () => {
    const { spawnNewWorktree } = await import('../../core/spawn.js');

    await postSpawn(app, {
      name: 'my-task',
      prompt: 'Fix it',
    });

    expect(vi.mocked(spawnNewWorktree)).toHaveBeenCalledWith(
      expect.objectContaining({ projectRoot: '/fake/project' }),
    );
  });
});
