import { describe, test, expect, vi, beforeEach, afterEach } from 'vitest';
import fs from 'node:fs/promises';
import path from 'node:path';
import YAML from 'yaml';
import type { SchedulesConfig } from '../types/schedule.js';

// Mock dependencies
vi.mock('../core/worktree.js', () => ({
  getRepoRoot: vi.fn(() => '/fake/project'),
}));

vi.mock('../lib/paths.js', async (importOriginal) => {
  const actual = await importOriginal() as Record<string, unknown>;
  return {
    ...actual,
    schedulesPath: vi.fn((root: string) => path.join(root, '.ppg', 'schedules.yaml')),
    manifestPath: vi.fn((root: string) => path.join(root, '.ppg', 'manifest.json')),
  };
});

// Mock cjs-compat to provide synchronous test doubles
const mockLock = vi.fn(async () => async () => {});
const mockWriteFileAtomic = vi.fn(async (_path: string, _content: string) => {});
vi.mock('../lib/cjs-compat.js', () => ({
  getLockfile: vi.fn(async () => ({ lock: mockLock })),
  getWriteFileAtomic: vi.fn(async () => mockWriteFileAtomic),
}));

// Spy on output
vi.mock('../lib/output.js', async (importOriginal) => {
  const actual = await importOriginal() as Record<string, unknown>;
  return {
    ...actual,
    output: vi.fn(),
    success: vi.fn(),
  };
});

// Import after mocks
const { cronAddCommand, cronRemoveCommand } = await import('./cron.js');
const { output, success } = await import('../lib/output.js');

// Helper to create a schedules.yaml fixture
function makeSchedulesYaml(entries: SchedulesConfig['schedules']): string {
  return YAML.stringify({ schedules: entries });
}

beforeEach(() => {
  vi.clearAllMocks();
  // Default: manifest exists so requireInit passes
  vi.spyOn(fs, 'access').mockResolvedValue(undefined);
  vi.spyOn(fs, 'mkdir').mockResolvedValue(undefined);
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe('cronAddCommand', () => {
  test('given valid options and no existing file, should create schedules.yaml with entry', async () => {
    vi.spyOn(fs, 'readFile').mockRejectedValue(Object.assign(new Error('ENOENT'), { code: 'ENOENT' }));

    await cronAddCommand({
      name: 'daily-build',
      cron: '0 9 * * *',
      swarm: 'build-all',
      project: '/fake/project',
    });

    expect(mockLock).toHaveBeenCalledOnce();
    expect(mockWriteFileAtomic).toHaveBeenCalledOnce();
    const written = YAML.parse(mockWriteFileAtomic.mock.calls[0][1] as string) as SchedulesConfig;
    expect(written.schedules).toHaveLength(1);
    expect(written.schedules[0].name).toBe('daily-build');
    expect(written.schedules[0].cron).toBe('0 9 * * *');
    expect(written.schedules[0].swarm).toBe('build-all');
    expect(success).toHaveBeenCalledWith('Schedule "daily-build" added');
  });

  test('given valid options and existing file, should append to schedules', async () => {
    const existing = makeSchedulesYaml([{ name: 'existing', cron: '0 0 * * *', swarm: 'test' }]);
    vi.spyOn(fs, 'readFile').mockResolvedValue(existing);

    await cronAddCommand({
      name: 'new-one',
      cron: '*/5 * * * *',
      prompt: 'quick-check',
      project: '/fake/project',
    });

    const written = YAML.parse(mockWriteFileAtomic.mock.calls[0][1] as string) as SchedulesConfig;
    expect(written.schedules).toHaveLength(2);
    expect(written.schedules[1].name).toBe('new-one');
    expect(written.schedules[1].prompt).toBe('quick-check');
  });

  test('given duplicate name, should throw INVALID_ARGS', async () => {
    const existing = makeSchedulesYaml([{ name: 'dup', cron: '0 0 * * *', swarm: 'test' }]);
    vi.spyOn(fs, 'readFile').mockResolvedValue(existing);

    await expect(cronAddCommand({
      name: 'dup',
      cron: '0 1 * * *',
      swarm: 'test',
      project: '/fake/project',
    })).rejects.toThrow('already exists');
  });

  test('given invalid name with special chars, should throw INVALID_ARGS', async () => {
    await expect(cronAddCommand({
      name: 'bad name!',
      cron: '0 0 * * *',
      swarm: 'test',
      project: '/fake/project',
    })).rejects.toThrow('Invalid schedule name');
  });

  test('given neither swarm nor prompt, should throw INVALID_ARGS', async () => {
    await expect(cronAddCommand({
      name: 'missing',
      cron: '0 0 * * *',
      project: '/fake/project',
    })).rejects.toThrow('Must specify either --swarm or --prompt');
  });

  test('given both swarm and prompt, should throw INVALID_ARGS', async () => {
    await expect(cronAddCommand({
      name: 'both',
      cron: '0 0 * * *',
      swarm: 'a',
      prompt: 'b',
      project: '/fake/project',
    })).rejects.toThrow('not both');
  });

  test('given vars, should include them in the entry', async () => {
    vi.spyOn(fs, 'readFile').mockRejectedValue(Object.assign(new Error('ENOENT'), { code: 'ENOENT' }));

    await cronAddCommand({
      name: 'with-vars',
      cron: '0 0 * * *',
      swarm: 'test',
      var: ['FOO=bar', 'BAZ=qux=val'],
      project: '/fake/project',
    });

    const written = YAML.parse(mockWriteFileAtomic.mock.calls[0][1] as string) as SchedulesConfig;
    expect(written.schedules[0].vars).toEqual({ FOO: 'bar', BAZ: 'qux=val' });
  });

  test('given invalid var format, should throw', async () => {
    vi.spyOn(fs, 'readFile').mockRejectedValue(Object.assign(new Error('ENOENT'), { code: 'ENOENT' }));

    await expect(cronAddCommand({
      name: 'bad-var',
      cron: '0 0 * * *',
      swarm: 'test',
      var: ['NOEQUALS'],
      project: '/fake/project',
    })).rejects.toThrow('expected KEY=VALUE');
  });

  test('given var with empty key like "=value", should throw', async () => {
    vi.spyOn(fs, 'readFile').mockRejectedValue(Object.assign(new Error('ENOENT'), { code: 'ENOENT' }));

    await expect(cronAddCommand({
      name: 'empty-key',
      cron: '0 0 * * *',
      swarm: 'test',
      var: ['=value'],
      project: '/fake/project',
    })).rejects.toThrow('key must not be empty');
  });

  test('given json option, should output JSON', async () => {
    vi.spyOn(fs, 'readFile').mockRejectedValue(Object.assign(new Error('ENOENT'), { code: 'ENOENT' }));

    await cronAddCommand({
      name: 'json-test',
      cron: '0 0 * * *',
      swarm: 'test',
      json: true,
      project: '/fake/project',
    });

    expect(output).toHaveBeenCalledWith(
      expect.objectContaining({ success: true, name: 'json-test' }),
      true,
    );
  });

  test('given malformed yaml (not an array), should throw fail-fast', async () => {
    vi.spyOn(fs, 'readFile').mockResolvedValue('schedules: "not an array"');

    await expect(cronAddCommand({
      name: 'test',
      cron: '0 0 * * *',
      swarm: 'test',
      project: '/fake/project',
    })).rejects.toThrow('Invalid schedules.yaml');
  });
});

describe('cronRemoveCommand', () => {
  test('given existing schedule, should remove it', async () => {
    const existing = makeSchedulesYaml([
      { name: 'keep', cron: '0 0 * * *', swarm: 'a' },
      { name: 'remove-me', cron: '0 1 * * *', swarm: 'b' },
    ]);
    vi.spyOn(fs, 'readFile').mockResolvedValue(existing);

    await cronRemoveCommand({
      name: 'remove-me',
      project: '/fake/project',
    });

    const written = YAML.parse(mockWriteFileAtomic.mock.calls[0][1] as string) as SchedulesConfig;
    expect(written.schedules).toHaveLength(1);
    expect(written.schedules[0].name).toBe('keep');
    expect(success).toHaveBeenCalledWith('Schedule "remove-me" removed');
  });

  test('given non-existent name, should throw', async () => {
    const existing = makeSchedulesYaml([{ name: 'exists', cron: '0 0 * * *', swarm: 'a' }]);
    vi.spyOn(fs, 'readFile').mockResolvedValue(existing);

    await expect(cronRemoveCommand({
      name: 'ghost',
      project: '/fake/project',
    })).rejects.toThrow('not found');
  });

  test('given no schedules file, should throw', async () => {
    vi.spyOn(fs, 'readFile').mockRejectedValue(Object.assign(new Error('ENOENT'), { code: 'ENOENT' }));

    await expect(cronRemoveCommand({
      name: 'test',
      project: '/fake/project',
    })).rejects.toThrow('not found');
  });

  test('given json option, should output JSON', async () => {
    const existing = makeSchedulesYaml([{ name: 'to-remove', cron: '0 0 * * *', swarm: 'a' }]);
    vi.spyOn(fs, 'readFile').mockResolvedValue(existing);

    await cronRemoveCommand({
      name: 'to-remove',
      json: true,
      project: '/fake/project',
    });

    expect(output).toHaveBeenCalledWith(
      expect.objectContaining({ success: true, name: 'to-remove' }),
      true,
    );
  });

  test('given malformed yaml, should throw fail-fast', async () => {
    vi.spyOn(fs, 'readFile').mockResolvedValue('random: stuff\nno_schedules_key: true');

    await expect(cronRemoveCommand({
      name: 'test',
      project: '/fake/project',
    })).rejects.toThrow('Invalid schedules.yaml');
  });
});
