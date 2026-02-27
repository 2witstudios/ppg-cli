import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

let tmpDir: string;
let globalDir: string;

vi.mock('../lib/paths.js', async () => {
  const actual = await vi.importActual<typeof import('../lib/paths.js')>('../lib/paths.js');
  return {
    ...actual,
    globalPromptsDir: () => path.join(globalDir, 'prompts'),
  };
});

// Dynamic import after mock setup
const { listPromptsWithSource, enrichEntryMetadata } = await import('./prompt.js');

beforeEach(async () => {
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'ppg-prompt-'));
  globalDir = path.join(tmpDir, 'global');
  await fs.mkdir(path.join(globalDir, 'prompts'), { recursive: true });
});

afterEach(async () => {
  await fs.rm(tmpDir, { recursive: true, force: true });
});

describe('listPromptsWithSource', () => {
  test('given no directories, should return empty array', async () => {
    const entries = await listPromptsWithSource(tmpDir);
    expect(entries).toEqual([]);
  });

  test('given local prompts, should return with local source', async () => {
    const localDir = path.join(tmpDir, '.ppg', 'prompts');
    await fs.mkdir(localDir, { recursive: true });
    await fs.writeFile(path.join(localDir, 'review.md'), '# Review\n');
    await fs.writeFile(path.join(localDir, 'fix.md'), '# Fix\n');

    const entries = await listPromptsWithSource(tmpDir);
    expect(entries).toEqual([
      { name: 'fix', source: 'local' },
      { name: 'review', source: 'local' },
    ]);
  });

  test('given global prompts, should return with global source', async () => {
    await fs.writeFile(path.join(globalDir, 'prompts', 'shared.md'), '# Shared\n');

    const entries = await listPromptsWithSource(tmpDir);
    expect(entries).toEqual([{ name: 'shared', source: 'global' }]);
  });

  test('given same name in local and global, should prefer local', async () => {
    const localDir = path.join(tmpDir, '.ppg', 'prompts');
    await fs.mkdir(localDir, { recursive: true });
    await fs.writeFile(path.join(localDir, 'shared.md'), '# Local\n');
    await fs.writeFile(path.join(globalDir, 'prompts', 'shared.md'), '# Global\n');

    const entries = await listPromptsWithSource(tmpDir);
    expect(entries).toEqual([{ name: 'shared', source: 'local' }]);
  });

  test('given non-.md files, should ignore them', async () => {
    const localDir = path.join(tmpDir, '.ppg', 'prompts');
    await fs.mkdir(localDir, { recursive: true });
    await fs.writeFile(path.join(localDir, 'valid.md'), '# Valid\n');
    await fs.writeFile(path.join(localDir, 'readme.txt'), 'not a prompt');

    const entries = await listPromptsWithSource(tmpDir);
    expect(entries).toEqual([{ name: 'valid', source: 'local' }]);
  });
});

describe('enrichEntryMetadata', () => {
  test('given markdown file, should extract description from first line', async () => {
    const dir = path.join(tmpDir, 'md');
    await fs.mkdir(dir, { recursive: true });
    await fs.writeFile(path.join(dir, 'task.md'), '# My Task\n\nBody here\n');

    const result = await enrichEntryMetadata('task', 'local', dir, dir);
    expect(result.description).toBe('My Task');
  });

  test('given template variables, should extract unique vars', async () => {
    const dir = path.join(tmpDir, 'md');
    await fs.mkdir(dir, { recursive: true });
    await fs.writeFile(
      path.join(dir, 'task.md'),
      '{{NAME}} and {{NAME}} and {{OTHER}}\n',
    );

    const result = await enrichEntryMetadata('task', 'local', dir, dir);
    expect(result.variables).toEqual(['NAME', 'OTHER']);
  });

  test('given no variables, should return empty array', async () => {
    const dir = path.join(tmpDir, 'md');
    await fs.mkdir(dir, { recursive: true });
    await fs.writeFile(path.join(dir, 'plain.md'), '# Plain text\n');

    const result = await enrichEntryMetadata('plain', 'local', dir, dir);
    expect(result.variables).toEqual([]);
  });

  test('given global source, should read from global dir', async () => {
    const localDir = path.join(tmpDir, 'local');
    const gDir = path.join(tmpDir, 'gbl');
    await fs.mkdir(gDir, { recursive: true });
    await fs.writeFile(path.join(gDir, 'task.md'), '# Global Task\n');

    const result = await enrichEntryMetadata('task', 'global', localDir, gDir);
    expect(result.description).toBe('Global Task');
    expect(result.source).toBe('global');
  });

  test('given empty first line, should skip to first non-empty line', async () => {
    const dir = path.join(tmpDir, 'md');
    await fs.mkdir(dir, { recursive: true });
    await fs.writeFile(path.join(dir, 'task.md'), '\n\n# Actual Title\n');

    const result = await enrichEntryMetadata('task', 'local', dir, dir);
    expect(result.description).toBe('Actual Title');
  });
});
