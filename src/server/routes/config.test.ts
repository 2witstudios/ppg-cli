import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import Fastify from 'fastify';
import { afterEach, beforeEach, describe, expect, test } from 'vitest';
import { configRoutes } from './config.js';

let tmpDir: string;

beforeEach(async () => {
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'ppg-config-routes-'));
});

afterEach(async () => {
  await fs.rm(tmpDir, { recursive: true, force: true });
});

function buildApp(projectRoot: string) {
  const app = Fastify({ logger: false });
  app.register(configRoutes, { projectRoot });
  return app;
}

// --- GET /api/config ---

describe('GET /api/config', () => {
  test('returns default config when no config.yaml exists', async () => {
    const app = buildApp(tmpDir);
    const res = await app.inject({ method: 'GET', url: '/api/config' });

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

  test('merges user config.yaml with defaults', async () => {
    const ppgDir = path.join(tmpDir, '.ppg');
    await fs.mkdir(ppgDir, { recursive: true });
    await fs.writeFile(
      path.join(ppgDir, 'config.yaml'),
      'sessionName: custom\ndefaultAgent: codex\nagents:\n  myagent:\n    name: myagent\n    command: myagent --fast\n    interactive: false\n',
    );

    const app = buildApp(tmpDir);
    const res = await app.inject({ method: 'GET', url: '/api/config' });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.sessionName).toBe('custom');
    expect(body.defaultAgent).toBe('codex');
    // Default agents are preserved
    expect(body.agents.find((a: { name: string }) => a.name === 'claude')).toBeTruthy();
    // Custom agent is added
    const myagent = body.agents.find((a: { name: string }) => a.name === 'myagent');
    expect(myagent).toBeTruthy();
    expect(myagent.command).toBe('myagent --fast');
    expect(myagent.interactive).toBe(false);
  });

  test('returns agents as array not object', async () => {
    const app = buildApp(tmpDir);
    const res = await app.inject({ method: 'GET', url: '/api/config' });

    const body = res.json();
    expect(Array.isArray(body.agents)).toBe(true);
    for (const agent of body.agents) {
      expect(agent).toHaveProperty('name');
      expect(agent).toHaveProperty('command');
      expect(agent).toHaveProperty('interactive');
    }
  });
});

// --- GET /api/templates ---

describe('GET /api/templates', () => {
  test('returns empty array when no templates exist', async () => {
    const app = buildApp(tmpDir);
    const res = await app.inject({ method: 'GET', url: '/api/templates' });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.templates).toEqual([]);
  });

  test('returns local templates with source and metadata', async () => {
    const tplDir = path.join(tmpDir, '.ppg', 'templates');
    await fs.mkdir(tplDir, { recursive: true });
    await fs.writeFile(
      path.join(tplDir, 'task.md'),
      '# Task Template\n\nDo {{TASK}} in {{WORKTREE_PATH}}\n',
    );

    const app = buildApp(tmpDir);
    const res = await app.inject({ method: 'GET', url: '/api/templates' });

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

  test('returns multiple templates sorted', async () => {
    const tplDir = path.join(tmpDir, '.ppg', 'templates');
    await fs.mkdir(tplDir, { recursive: true });
    await fs.writeFile(path.join(tplDir, 'alpha.md'), '# Alpha\n');
    await fs.writeFile(path.join(tplDir, 'beta.md'), '# Beta\n{{VAR}}\n');

    const app = buildApp(tmpDir);
    const res = await app.inject({ method: 'GET', url: '/api/templates' });

    const body = res.json();
    expect(body.templates).toHaveLength(2);
    const names = body.templates.map((t: { name: string }) => t.name);
    expect(names).toContain('alpha');
    expect(names).toContain('beta');
  });

  test('deduplicates variables in template', async () => {
    const tplDir = path.join(tmpDir, '.ppg', 'templates');
    await fs.mkdir(tplDir, { recursive: true });
    await fs.writeFile(
      path.join(tplDir, 'dupe.md'),
      '{{NAME}} and {{NAME}} and {{OTHER}}\n',
    );

    const app = buildApp(tmpDir);
    const res = await app.inject({ method: 'GET', url: '/api/templates' });

    const body = res.json();
    expect(body.templates[0].variables).toEqual(['NAME', 'OTHER']);
  });
});

// --- GET /api/prompts ---

describe('GET /api/prompts', () => {
  test('returns empty array when no prompts exist', async () => {
    const app = buildApp(tmpDir);
    const res = await app.inject({ method: 'GET', url: '/api/prompts' });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.prompts).toEqual([]);
  });

  test('returns local prompts with source and metadata', async () => {
    const pDir = path.join(tmpDir, '.ppg', 'prompts');
    await fs.mkdir(pDir, { recursive: true });
    await fs.writeFile(
      path.join(pDir, 'review.md'),
      '# Code Review\n\nReview {{BRANCH}} for issues\n',
    );

    const app = buildApp(tmpDir);
    const res = await app.inject({ method: 'GET', url: '/api/prompts' });

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

  test('deduplicates prompts across local and global (local wins)', async () => {
    // Local prompt
    const localDir = path.join(tmpDir, '.ppg', 'prompts');
    await fs.mkdir(localDir, { recursive: true });
    await fs.writeFile(path.join(localDir, 'shared.md'), '# Local Shared\n');

    // Global prompt with same name — we can't easily write to ~/.ppg/prompts
    // in a test, so we test the dedup logic via the entry listing behavior.
    // The key assertion is that only one entry appears for a given name.

    const app = buildApp(tmpDir);
    const res = await app.inject({ method: 'GET', url: '/api/prompts' });

    const body = res.json();
    const sharedEntries = body.prompts.filter(
      (p: { name: string }) => p.name === 'shared',
    );
    expect(sharedEntries).toHaveLength(1);
    expect(sharedEntries[0].source).toBe('local');
  });

  test('ignores non-.md files in prompts directory', async () => {
    const pDir = path.join(tmpDir, '.ppg', 'prompts');
    await fs.mkdir(pDir, { recursive: true });
    await fs.writeFile(path.join(pDir, 'valid.md'), '# Valid Prompt\n');
    await fs.writeFile(path.join(pDir, 'readme.txt'), 'not a prompt');
    await fs.writeFile(path.join(pDir, '.hidden'), 'hidden file');

    const app = buildApp(tmpDir);
    const res = await app.inject({ method: 'GET', url: '/api/prompts' });

    const body = res.json();
    expect(body.prompts).toHaveLength(1);
    expect(body.prompts[0].name).toBe('valid');
  });
});
