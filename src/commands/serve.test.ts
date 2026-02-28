import { describe, test, expect, vi, beforeEach, afterEach } from 'vitest';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

// Mock dependencies for global serve
vi.mock('../core/tmux.js', () => ({
  ensureSession: vi.fn(),
  createWindow: vi.fn(() => 'ppg-serve:1'),
  sendKeys: vi.fn(),
  listSessionWindows: vi.fn(() => []),
  killWindow: vi.fn(),
}));

vi.mock('../lib/paths.js', async (importOriginal) => {
  const actual = await importOriginal() as Record<string, unknown>;
  const fakeGlobalDir = path.join(os.tmpdir(), 'ppg-test-global');
  return {
    ...actual,
    globalPpgDir: vi.fn(() => fakeGlobalDir),
    globalServePidPath: vi.fn(() => path.join(fakeGlobalDir, 'serve.pid')),
    globalServeJsonPath: vi.fn(() => path.join(fakeGlobalDir, 'serve.json')),
    globalServeLogPath: vi.fn(() => path.join(fakeGlobalDir, 'logs', 'serve.log')),
  };
});

vi.mock('../core/worktree.js', () => ({
  getRepoRoot: vi.fn(() => { throw new Error('Not in a git repo'); }),
}));

vi.mock('../core/manifest.js', () => ({
  requireManifest: vi.fn(() => { throw new Error('Not initialized'); }),
  readManifest: vi.fn(() => ({ sessionName: 'ppg-test', agents: {}, worktrees: {} })),
}));

vi.mock('../core/projects.js', () => ({
  registerProject: vi.fn(),
}));

vi.mock('../server/index.js', () => ({
  startServer: vi.fn(),
}));

vi.mock('../lib/output.js', async (importOriginal) => {
  const actual = await importOriginal() as Record<string, unknown>;
  return {
    ...actual,
    output: vi.fn(),
    info: vi.fn(),
    success: vi.fn(),
    warn: vi.fn(),
  };
});

const { serveStartCommand, serveStopCommand, serveStatusCommand, serveDaemonCommand, buildPairingUrl, getLocalIp, verifyToken } = await import('./serve.js');
const { output, success, warn, info } = await import('../lib/output.js');
const { globalServePidPath, globalServeJsonPath } = await import('../lib/paths.js');
const tmux = await import('../core/tmux.js');
const { startServer } = await import('../server/index.js');

beforeEach(() => {
  vi.clearAllMocks();
  // Mock fs.readFile to return ENOENT for PID files by default (no running server)
  vi.spyOn(fs, 'readFile').mockRejectedValue(Object.assign(new Error('ENOENT'), { code: 'ENOENT' }));
  vi.spyOn(fs, 'mkdir').mockResolvedValue(undefined);
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe('serveStartCommand', () => {
  test('given no server running, should start daemon in global tmux session', async () => {
    await serveStartCommand({ port: 3000, host: 'localhost' });

    expect(tmux.ensureSession).toHaveBeenCalledWith('ppg-serve');
    expect(tmux.createWindow).toHaveBeenCalledWith('ppg-serve', 'ppg-serve', os.homedir());
    expect(tmux.sendKeys).toHaveBeenCalledWith('ppg-serve:1', 'ppg serve _daemon --port 3000 --host localhost');
    expect(success).toHaveBeenCalledWith('Serve daemon starting in tmux window: ppg-serve:1');
  });

  test('given custom port and host, should pass them to daemon command', async () => {
    await serveStartCommand({ port: 8080, host: '0.0.0.0' });

    expect(tmux.sendKeys).toHaveBeenCalledWith('ppg-serve:1', 'ppg serve _daemon --port 8080 --host 0.0.0.0');
  });

  test('given server already running, should warn and return', async () => {
    const pidPath = globalServePidPath();
    const jsonPath = globalServeJsonPath();
    vi.mocked(fs.readFile).mockImplementation(async (filePath: any) => {
      if (String(filePath) === pidPath) return '12345';
      if (String(filePath) === jsonPath) return JSON.stringify({ port: 3000, host: 'localhost', startedAt: '2026-01-01' });
      throw Object.assign(new Error('ENOENT'), { code: 'ENOENT' });
    });
    vi.spyOn(process, 'kill').mockImplementation(() => true);

    await serveStartCommand({ port: 3000, host: 'localhost' });

    expect(tmux.createWindow).not.toHaveBeenCalled();
    expect(warn).toHaveBeenCalledWith('Serve daemon is already running (PID: 12345)');

    vi.mocked(process.kill).mockRestore();
  });

  test('given json option, should output JSON on success', async () => {
    await serveStartCommand({ port: 3000, host: 'localhost', json: true });

    expect(output).toHaveBeenCalledWith(
      expect.objectContaining({ success: true, port: 3000, host: 'localhost', tmuxWindow: 'ppg-serve:1' }),
      true,
    );
  });

  test('given invalid host with shell metacharacters, should throw INVALID_ARGS', async () => {
    await expect(serveStartCommand({ port: 3000, host: 'localhost; rm -rf /' }))
      .rejects.toThrow('Invalid host');
  });
});

describe('serveStopCommand', () => {
  test('given running server, should kill process and clean up', async () => {
    const pidPath = globalServePidPath();
    vi.mocked(fs.readFile).mockImplementation(async (filePath: any) => {
      if (String(filePath) === pidPath) return '99999';
      throw Object.assign(new Error('ENOENT'), { code: 'ENOENT' });
    });
    const mockKill = vi.spyOn(process, 'kill').mockImplementation(() => true);
    vi.spyOn(fs, 'unlink').mockResolvedValue(undefined);

    await serveStopCommand({});

    expect(mockKill).toHaveBeenCalledWith(99999, 'SIGTERM');
    expect(success).toHaveBeenCalledWith('Serve daemon stopped (PID: 99999)');

    mockKill.mockRestore();
  });

  test('given no server running, should warn', async () => {
    await serveStopCommand({});

    expect(warn).toHaveBeenCalledWith('Serve daemon is not running');
  });

  test('given json option and not running, should output JSON', async () => {
    await serveStopCommand({ json: true });

    expect(output).toHaveBeenCalledWith(
      expect.objectContaining({ success: false, error: 'Serve daemon is not running' }),
      true,
    );
  });
});

describe('serveStatusCommand', () => {
  test('given no server running, should warn', async () => {
    await serveStatusCommand({});

    expect(warn).toHaveBeenCalledWith('Serve daemon is not running');
  });

  test('given json option and not running, should output JSON', async () => {
    await serveStatusCommand({ json: true });

    expect(output).toHaveBeenCalledWith(
      expect.objectContaining({ running: false, pid: null, recentLog: [] }),
      true,
    );
  });
});

describe('serveDaemonCommand', () => {
  test('given valid options, should call startServer without projectRoot', async () => {
    await serveDaemonCommand({ port: 4000, host: '0.0.0.0' });

    expect(startServer).toHaveBeenCalledWith({ port: 4000, host: '0.0.0.0', token: undefined });
  });
});

describe('buildPairingUrl', () => {
  test('given valid params, should encode all fields into ppg:// URL', () => {
    const url = buildPairingUrl({
      host: '192.168.1.10',
      port: 7700,
      fingerprint: 'AA:BB:CC',
      token: 'test-token-123',
    });

    expect(url).toContain('ppg://connect');
    expect(url).toContain('host=192.168.1.10');
    expect(url).toContain('port=7700');
    expect(url).toContain('ca=AA%3ABB%3ACC');
    expect(url).toContain('token=test-token-123');
  });

  test('given special characters in token, should URL-encode them', () => {
    const url = buildPairingUrl({
      host: '10.0.0.1',
      port: 8080,
      fingerprint: 'DE:AD:BE:EF',
      token: 'a+b/c=d',
    });

    expect(url).toContain('token=a%2Bb%2Fc%3Dd');
  });
});

describe('getLocalIp', () => {
  test('should return a non-empty string', () => {
    const ip = getLocalIp();
    expect(ip).toBeTruthy();
    expect(typeof ip).toBe('string');
  });

  test('should return a valid IPv4 address', () => {
    const ip = getLocalIp();
    const ipv4Pattern = /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/;
    expect(ip).toMatch(ipv4Pattern);
  });
});

describe('verifyToken', () => {
  test('given matching tokens, should return true', () => {
    expect(verifyToken('correct-token', 'correct-token')).toBe(true);
  });

  test('given different tokens of same length, should return false', () => {
    expect(verifyToken('aaaa-bbbb-cccc', 'xxxx-yyyy-zzzz')).toBe(false);
  });

  test('given different length tokens, should return false', () => {
    expect(verifyToken('short', 'much-longer-token')).toBe(false);
  });

  test('given empty provided token, should return false', () => {
    expect(verifyToken('', 'expected-token')).toBe(false);
  });

  test('given both empty, should return true', () => {
    expect(verifyToken('', '')).toBe(true);
  });
});
