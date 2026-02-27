import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import Fastify, { type FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { configRoutes } from './config.js';

let tmpDir: string;
let globalDir: string;
let app: FastifyInstance;

vi.mock('../../lib/paths.js', async () => {
  const actual = await vi.importActual<typeof import('../../lib/paths.js')>('../../lib/paths.js');
  return {
    ...actual,
    globalTemplatesDir: () => path.join(globalDir, 'templates'),
    globalPromptsDir: () => path.join(globalDir, 'prompts'),
  };
});

beforeEach(async () => {
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'ppg-config-routes-'));
  globalDir = path.join(tmpDir, 'global');
  await fs.mkdir(path.join(globalDir, 'templates'), { recursive: true });
  await fs.mkdir(path.join(globalDir, 'prompts'), { recursive: true });
});

afterEach(async () => {
  await app?.close();
  await fs.rm(tmpDir, { recursive: true, force: true });
});

function buildApp(projectRoot: string) {
  app = Fastify({ logger: false });
  app.register(configRoutes, { projectRoot });
  return app;
}

// --- GET /api/config ---

describe('GET /api/config', () => {
  test('given no config.yaml, should return default config', async () => {
    const server = buildApp(tmpDir);
    const res = await server.inject({ method: 'GET', url: '/api/config' });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.sessionName).toBe('ppg');
    expect(body.defaultAgent).toBe('claude');
    expect(body.agents).toBeInstanceOf(Array);
    expect(body.agents.length).toBeGreaterThanOrEqual(3);
    expect(body.agents.find((a: { name: string }) => a.name === 'claude')).toBeTruthy();
    expect(body.envFiles).toEqual(['.env', '.env.local']);
    expect(body.symlinkNodeModules).toBe(true);
  });

  test('given user config.yaml, should merge with defaults', async () => {
    const ppgDir = path.join(tmpDir, '.ppg');
    await fs.mkdir(ppgDir, { recursive: true });
    await fs.writeFile(
      path.join(ppgDir, 'config.yaml'),
      'sessionName: custom\ndefaultAgent: codex\nagents:\n  myagent:\n    name: myagent\n    command: myagent --fast\n    interactive: false\n',
    );

    const server = buildApp(tmpDir);
    const res = await server.inject({ method: 'GET', url: '/api/config' });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.sessionName).toBe('custom');
    expect(body.defaultAgent).toBe('codex');
    expect(body.agents.find((a: { name: string }) => a.name === 'claude')).toBeTruthy();
    const myagent = body.agents.find((a: { name: string }) => a.name === 'myagent');
    expect(myagent).toBeTruthy();
    expect(myagent.command).toBe('myagent --fast');
    expect(myagent.interactive).toBe(false);
  });

  test('given invalid YAML, should return 500 error', async () => {
    const ppgDir = path.join(tmpDir, '.ppg');
    await fs.mkdir(ppgDir, { recursive: true });
    await fs.writeFile(path.join(ppgDir, 'config.yaml'), ':\n  bad: [yaml\n');

    const server = buildApp(tmpDir);
    const res = await server.inject({ method: 'GET', url: '/api/config' });

    expect(res.statusCode).toBe(500);
  });
});

// --- GET /api/templates ---

describe('GET /api/templates', () => {
  test('given no template dirs, should return empty array', async () => {
    const server = buildApp(tmpDir);
    const res = await server.inject({ method: 'GET', url: '/api/templates' });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.templates).toEqual([]);
  });

  test('given local template, should return source and metadata', async () => {
    const tplDir = path.join(tmpDir, '.ppg', 'templates');
    await fs.mkdir(tplDir, { recursive: true });
    await fs.writeFile(
      path.join(tplDir, 'task.md'),
      '# Task Template\n\nDo {{TASK}} in {{WORKTREE_PATH}}\n',
    );

    const server = buildApp(tmpDir);
    const res = await server.inject({ method: 'GET', url: '/api/templates' });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.templates).toHaveLength(1);
    expect(body.templates[0]).toEqual({
      name: 'task',
      description: 'Task Template',
      variables: ['TASK', 'WORKTREE_PATH'],
      source: 'local',
    });
  });

  test('given global template, should return with global source', async () => {
    await fs.writeFile(
      path.join(globalDir, 'templates', 'shared.md'),
      '# Global Template\n\n{{VAR}}\n',
    );

    const server = buildApp(tmpDir);
    const res = await server.inject({ method: 'GET', url: '/api/templates' });

    const body = res.json();
    expect(body.templates).toHaveLength(1);
    expect(body.templates[0].name).toBe('shared');
    expect(body.templates[0].source).toBe('global');
  });

  test('given same name in local and global, should prefer local', async () => {
    const tplDir = path.join(tmpDir, '.ppg', 'templates');
    await fs.mkdir(tplDir, { recursive: true });
    await fs.writeFile(path.join(tplDir, 'shared.md'), '# Local Version\n');
    await fs.writeFile(path.join(globalDir, 'templates', 'shared.md'), '# Global Version\n');

    const server = buildApp(tmpDir);
    const res = await server.inject({ method: 'GET', url: '/api/templates' });

    const body = res.json();
    const shared = body.templates.filter((t: { name: string }) => t.name === 'shared');
    expect(shared).toHaveLength(1);
    expect(shared[0].source).toBe('local');
    expect(shared[0].description).toBe('Local Version');
  });

  test('given duplicate variables, should deduplicate', async () => {
    const tplDir = path.join(tmpDir, '.ppg', 'templates');
    await fs.mkdir(tplDir, { recursive: true });
    await fs.writeFile(
      path.join(tplDir, 'dupe.md'),
      '{{NAME}} and {{NAME}} and {{OTHER}}\n',
    );

    const server = buildApp(tmpDir);
    const res = await server.inject({ method: 'GET', url: '/api/templates' });

    const body = res.json();
    expect(body.templates[0].variables).toEqual(['NAME', 'OTHER']);
  });
});

// --- GET /api/prompts ---

describe('GET /api/prompts', () => {
  test('given no prompt dirs, should return empty array', async () => {
    const server = buildApp(tmpDir);
    const res = await server.inject({ method: 'GET', url: '/api/prompts' });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.prompts).toEqual([]);
  });

  test('given local prompt, should return source and metadata', async () => {
    const pDir = path.join(tmpDir, '.ppg', 'prompts');
    await fs.mkdir(pDir, { recursive: true });
    await fs.writeFile(
      path.join(pDir, 'review.md'),
      '# Code Review\n\nReview {{BRANCH}} for issues\n',
    );

    const server = buildApp(tmpDir);
    const res = await server.inject({ method: 'GET', url: '/api/prompts' });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.prompts).toHaveLength(1);
    expect(body.prompts[0]).toEqual({
      name: 'review',
      description: 'Code Review',
      variables: ['BRANCH'],
      source: 'local',
    });
  });

  test('given same name in local and global, should prefer local', async () => {
    const localDir = path.join(tmpDir, '.ppg', 'prompts');
    await fs.mkdir(localDir, { recursive: true });
    await fs.writeFile(path.join(localDir, 'shared.md'), '# Local Shared\n');
    await fs.writeFile(path.join(globalDir, 'prompts', 'shared.md'), '# Global Shared\n');

    const server = buildApp(tmpDir);
    const res = await server.inject({ method: 'GET', url: '/api/prompts' });

    const body = res.json();
    const shared = body.prompts.filter((p: { name: string }) => p.name === 'shared');
    expect(shared).toHaveLength(1);
    expect(shared[0].source).toBe('local');
    expect(shared[0].description).toBe('Local Shared');
  });

  test('given global-only prompt, should return with global source', async () => {
    await fs.writeFile(
      path.join(globalDir, 'prompts', 'global-only.md'),
      '# Global Prompt\n\n{{WHO}}\n',
    );

    const server = buildApp(tmpDir);
    const res = await server.inject({ method: 'GET', url: '/api/prompts' });

    const body = res.json();
    expect(body.prompts).toHaveLength(1);
    expect(body.prompts[0].name).toBe('global-only');
    expect(body.prompts[0].source).toBe('global');
    expect(body.prompts[0].variables).toEqual(['WHO']);
  });

  test('given non-.md files, should ignore them', async () => {
    const pDir = path.join(tmpDir, '.ppg', 'prompts');
    await fs.mkdir(pDir, { recursive: true });
    await fs.writeFile(path.join(pDir, 'valid.md'), '# Valid Prompt\n');
    await fs.writeFile(path.join(pDir, 'readme.txt'), 'not a prompt');
    await fs.writeFile(path.join(pDir, '.hidden'), 'hidden file');

    const server = buildApp(tmpDir);
    const res = await server.inject({ method: 'GET', url: '/api/prompts' });

    const body = res.json();
    expect(body.prompts).toHaveLength(1);
    expect(body.prompts[0].name).toBe('valid');
  });
});
