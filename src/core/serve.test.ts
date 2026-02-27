import { describe, test, expect, vi, beforeEach, afterEach } from 'vitest';
import fs from 'node:fs/promises';
import path from 'node:path';

vi.mock('../lib/paths.js', async (importOriginal) => {
  const actual = await importOriginal() as Record<string, unknown>;
  return {
    ...actual,
    servePidPath: vi.fn((root: string) => path.join(root, '.ppg', 'serve.pid')),
    serveJsonPath: vi.fn((root: string) => path.join(root, '.ppg', 'serve.json')),
    serveLogPath: vi.fn((root: string) => path.join(root, '.ppg', 'logs', 'serve.log')),
    logsDir: vi.fn((root: string) => path.join(root, '.ppg', 'logs')),
  };
});

const { getServePid, isServeRunning, getServeInfo } = await import('./serve.js');

beforeEach(() => {
  vi.clearAllMocks();
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe('getServePid', () => {
  test('given no PID file, should return null', async () => {
    vi.spyOn(fs, 'readFile').mockRejectedValue(Object.assign(new Error('ENOENT'), { code: 'ENOENT' }));

    const pid = await getServePid('/fake/project');
    expect(pid).toBeNull();
  });

  test('given PID file with valid alive PID, should return the PID', async () => {
    vi.spyOn(fs, 'readFile').mockResolvedValue(String(process.pid));

    const pid = await getServePid('/fake/project');
    expect(pid).toBe(process.pid);
  });

  test('given PID file with dead process, should clean up and return null', async () => {
    vi.spyOn(fs, 'readFile').mockResolvedValue('999999999');
    vi.spyOn(fs, 'unlink').mockResolvedValue(undefined);

    const pid = await getServePid('/fake/project');
    expect(pid).toBeNull();
    expect(fs.unlink).toHaveBeenCalledWith('/fake/project/.ppg/serve.pid');
  });

  test('given PID file with non-numeric content, should clean up and return null', async () => {
    vi.spyOn(fs, 'readFile').mockResolvedValue('not-a-number');
    vi.spyOn(fs, 'unlink').mockResolvedValue(undefined);

    const pid = await getServePid('/fake/project');
    expect(pid).toBeNull();
    expect(fs.unlink).toHaveBeenCalledWith('/fake/project/.ppg/serve.pid');
  });
});

describe('isServeRunning', () => {
  test('given no PID file, should return false', async () => {
    vi.spyOn(fs, 'readFile').mockRejectedValue(Object.assign(new Error('ENOENT'), { code: 'ENOENT' }));

    const running = await isServeRunning('/fake/project');
    expect(running).toBe(false);
  });

  test('given valid alive PID, should return true', async () => {
    vi.spyOn(fs, 'readFile').mockResolvedValue(String(process.pid));

    const running = await isServeRunning('/fake/project');
    expect(running).toBe(true);
  });
});

describe('getServeInfo', () => {
  test('given no serve.json, should return null', async () => {
    vi.spyOn(fs, 'readFile').mockRejectedValue(Object.assign(new Error('ENOENT'), { code: 'ENOENT' }));

    const info = await getServeInfo('/fake/project');
    expect(info).toBeNull();
  });

  test('given valid serve.json, should return parsed info', async () => {
    const serveInfo = {
      pid: 12345,
      port: 3000,
      host: 'localhost',
      startedAt: '2026-01-01T00:00:00.000Z',
    };
    vi.spyOn(fs, 'readFile').mockResolvedValue(JSON.stringify(serveInfo));

    const info = await getServeInfo('/fake/project');
    expect(info).toEqual(serveInfo);
  });
});
