import { describe, test, expect, vi, beforeEach, afterEach } from 'vitest';
import fs from 'node:fs/promises';
import path from 'node:path';

// Mock dependencies
vi.mock('../core/worktree.js', () => ({
  getRepoRoot: vi.fn(() => '/fake/project'),
}));

vi.mock('../core/manifest.js', () => ({
  requireManifest: vi.fn(() => ({ sessionName: 'ppg-test' })),
  readManifest: vi.fn(() => ({ sessionName: 'ppg-test' })),
}));

vi.mock('../core/tmux.js', () => ({
  ensureSession: vi.fn(),
  createWindow: vi.fn(() => 'ppg-test:1'),
  sendKeys: vi.fn(),
  listSessionWindows: vi.fn(() => []),
  killWindow: vi.fn(),
}));

vi.mock('../lib/paths.js', async (importOriginal) => {
  const actual = await importOriginal() as Record<string, unknown>;
  return {
    ...actual,
    manifestPath: vi.fn((root: string) => path.join(root, '.ppg', 'manifest.json')),
    servePidPath: vi.fn((root: string) => path.join(root, '.ppg', 'serve.pid')),
    serveJsonPath: vi.fn((root: string) => path.join(root, '.ppg', 'serve.json')),
    serveLogPath: vi.fn((root: string) => path.join(root, '.ppg', 'logs', 'serve.log')),
    logsDir: vi.fn((root: string) => path.join(root, '.ppg', 'logs')),
  };
});

vi.mock('../core/serve.js', async (importOriginal) => {
  const actual = await importOriginal() as Record<string, unknown>;
  return {
    ...actual,
    isServeRunning: vi.fn(() => false),
    getServePid: vi.fn(() => null),
    getServeInfo: vi.fn(() => null),
    readServeLog: vi.fn(() => []),
    runServeDaemon: vi.fn(),
  };
});

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
const { isServeRunning, getServePid, getServeInfo, readServeLog, runServeDaemon } = await import('../core/serve.js');
const { requireManifest } = await import('../core/manifest.js');
const tmux = await import('../core/tmux.js');

beforeEach(() => {
  vi.clearAllMocks();
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe('serveStartCommand', () => {
  test('given no server running, should start daemon in tmux window', async () => {
    await serveStartCommand({ port: 3000, host: 'localhost' });

    expect(requireManifest).toHaveBeenCalledWith('/fake/project');
    expect(tmux.ensureSession).toHaveBeenCalledWith('ppg-test');
    expect(tmux.createWindow).toHaveBeenCalledWith('ppg-test', 'ppg-serve', '/fake/project');
    expect(tmux.sendKeys).toHaveBeenCalledWith('ppg-test:1', 'ppg serve _daemon --port 3000 --host localhost');
    expect(success).toHaveBeenCalledWith('Serve daemon starting in tmux window: ppg-test:1');
  });

  test('given custom port and host, should pass them to daemon command', async () => {
    await serveStartCommand({ port: 8080, host: '0.0.0.0' });

    expect(tmux.sendKeys).toHaveBeenCalledWith('ppg-test:1', 'ppg serve _daemon --port 8080 --host 0.0.0.0');
  });

  test('given server already running, should warn and return', async () => {
    vi.mocked(isServeRunning).mockResolvedValue(true);
    vi.mocked(getServePid).mockResolvedValue(12345);
    vi.mocked(getServeInfo).mockResolvedValue({
      pid: 12345,
      port: 3000,
      host: 'localhost',
      startedAt: '2026-01-01T00:00:00.000Z',
    });

    await serveStartCommand({ port: 3000, host: 'localhost' });

    expect(tmux.createWindow).not.toHaveBeenCalled();
    expect(warn).toHaveBeenCalledWith('Serve daemon is already running (PID: 12345)');
    expect(info).toHaveBeenCalledWith('Listening on localhost:3000');
  });

  test('given json option, should output JSON on success', async () => {
    await serveStartCommand({ port: 3000, host: 'localhost', json: true });

    expect(output).toHaveBeenCalledWith(
      expect.objectContaining({ success: true, port: 3000, host: 'localhost', tmuxWindow: 'ppg-test:1' }),
      true,
    );
  });

  test('given json option and already running, should output JSON error', async () => {
    vi.mocked(isServeRunning).mockResolvedValue(true);
    vi.mocked(getServePid).mockResolvedValue(12345);
    vi.mocked(getServeInfo).mockResolvedValue({
      pid: 12345,
      port: 3000,
      host: 'localhost',
      startedAt: '2026-01-01T00:00:00.000Z',
    });

    await serveStartCommand({ port: 3000, host: 'localhost', json: true });

    expect(output).toHaveBeenCalledWith(
      expect.objectContaining({ success: false, error: 'Serve daemon is already running', pid: 12345 }),
      true,
    );
  });

  test('given project not initialized, should throw NotInitializedError', async () => {
    const err = Object.assign(new Error('Not initialized'), { code: 'NOT_INITIALIZED' });
    vi.mocked(requireManifest).mockRejectedValue(err);

    await expect(serveStartCommand({ port: 3000, host: 'localhost' })).rejects.toThrow('Not initialized');
    expect(tmux.createWindow).not.toHaveBeenCalled();
  });

  test('given invalid host with shell metacharacters, should throw INVALID_ARGS', async () => {
    await expect(serveStartCommand({ port: 3000, host: 'localhost; rm -rf /' }))
      .rejects.toThrow('Invalid host');
  });
});

describe('serveStopCommand', () => {
  test('given running server, should kill process and clean up', async () => {
    vi.mocked(getServePid).mockResolvedValue(99999);
    const mockKill = vi.spyOn(process, 'kill').mockImplementation(() => true);
    vi.spyOn(fs, 'unlink').mockResolvedValue(undefined);

    await serveStopCommand({});

    expect(mockKill).toHaveBeenCalledWith(99999, 'SIGTERM');
    expect(fs.unlink).toHaveBeenCalledWith('/fake/project/.ppg/serve.pid');
    expect(fs.unlink).toHaveBeenCalledWith('/fake/project/.ppg/serve.json');
    expect(success).toHaveBeenCalledWith('Serve daemon stopped (PID: 99999)');

    mockKill.mockRestore();
  });

  test('given no server running, should warn', async () => {
    await serveStopCommand({});

    expect(warn).toHaveBeenCalledWith('Serve daemon is not running');
  });

  test('given running server with tmux window, should kill the tmux window', async () => {
    vi.mocked(getServePid).mockResolvedValue(99999);
    vi.spyOn(process, 'kill').mockImplementation(() => true);
    vi.spyOn(fs, 'unlink').mockResolvedValue(undefined);
    vi.mocked(tmux.listSessionWindows).mockResolvedValue([
      { index: 0, name: 'bash' },
      { index: 1, name: 'ppg-serve' },
    ]);

    await serveStopCommand({});

    expect(tmux.killWindow).toHaveBeenCalledWith('ppg-test:1');

    vi.mocked(process.kill).mockRestore();
  });

  test('given process already dead when killing, should still clean up files', async () => {
    vi.mocked(getServePid).mockResolvedValue(99999);
    vi.spyOn(process, 'kill').mockImplementation(() => { throw new Error('ESRCH'); });
    vi.spyOn(fs, 'unlink').mockResolvedValue(undefined);

    await serveStopCommand({});

    expect(fs.unlink).toHaveBeenCalledWith('/fake/project/.ppg/serve.pid');
    expect(fs.unlink).toHaveBeenCalledWith('/fake/project/.ppg/serve.json');
    expect(success).toHaveBeenCalledWith('Serve daemon stopped (PID: 99999)');

    vi.mocked(process.kill).mockRestore();
  });

  test('given json option and not running, should output JSON', async () => {
    await serveStopCommand({ json: true });

    expect(output).toHaveBeenCalledWith(
      expect.objectContaining({ success: false, error: 'Serve daemon is not running' }),
      true,
    );
  });

  test('given json option and running, should output JSON on success', async () => {
    vi.mocked(getServePid).mockResolvedValue(88888);
    vi.spyOn(process, 'kill').mockImplementation(() => true);
    vi.spyOn(fs, 'unlink').mockResolvedValue(undefined);

    await serveStopCommand({ json: true });

    expect(output).toHaveBeenCalledWith(
      expect.objectContaining({ success: true, pid: 88888 }),
      true,
    );

    vi.mocked(process.kill).mockRestore();
  });
});

describe('serveStatusCommand', () => {
  test('given running server, should show status with connection info', async () => {
    vi.mocked(isServeRunning).mockResolvedValue(true);
    vi.mocked(getServePid).mockResolvedValue(12345);
    vi.mocked(getServeInfo).mockResolvedValue({
      pid: 12345,
      port: 3000,
      host: 'localhost',
      startedAt: '2026-01-01T00:00:00.000Z',
    });
    vi.mocked(readServeLog).mockResolvedValue(['[2026-01-01T00:00:00.000Z] Started']);

    await serveStatusCommand({});

    expect(success).toHaveBeenCalledWith('Serve daemon is running (PID: 12345)');
    expect(info).toHaveBeenCalledWith('Listening on localhost:3000');
    expect(info).toHaveBeenCalledWith('Started at 2026-01-01T00:00:00.000Z');
  });

  test('given no server running, should warn', async () => {
    await serveStatusCommand({});

    expect(warn).toHaveBeenCalledWith('Serve daemon is not running');
  });

  test('given json option and running, should output JSON with connection info', async () => {
    vi.mocked(isServeRunning).mockResolvedValue(true);
    vi.mocked(getServePid).mockResolvedValue(12345);
    vi.mocked(getServeInfo).mockResolvedValue({
      pid: 12345,
      port: 3000,
      host: 'localhost',
      startedAt: '2026-01-01T00:00:00.000Z',
    });
    vi.mocked(readServeLog).mockResolvedValue([]);

    await serveStatusCommand({ json: true });

    expect(output).toHaveBeenCalledWith(
      expect.objectContaining({
        running: true,
        pid: 12345,
        host: 'localhost',
        port: 3000,
        startedAt: '2026-01-01T00:00:00.000Z',
        recentLog: [],
      }),
      true,
    );
  });

  test('given json option and not running, should output JSON', async () => {
    await serveStatusCommand({ json: true });

    expect(output).toHaveBeenCalledWith(
      expect.objectContaining({ running: false, pid: null, recentLog: [] }),
      true,
    );
  });

  test('given custom lines option, should pass to readServeLog', async () => {
    await serveStatusCommand({ lines: 50 });

    expect(readServeLog).toHaveBeenCalledWith('/fake/project', 50);
  });
});

describe('serveDaemonCommand', () => {
  test('given initialized project, should call runServeDaemon with correct args', async () => {
    await serveDaemonCommand({ port: 4000, host: '0.0.0.0' });

    expect(requireManifest).toHaveBeenCalledWith('/fake/project');
    expect(runServeDaemon).toHaveBeenCalledWith('/fake/project', 4000, '0.0.0.0');
  });

  test('given project not initialized, should throw', async () => {
    const err = Object.assign(new Error('Not initialized'), { code: 'NOT_INITIALIZED' });
    vi.mocked(requireManifest).mockRejectedValue(err);

    await expect(serveDaemonCommand({ port: 3000, host: 'localhost' })).rejects.toThrow('Not initialized');
    expect(runServeDaemon).not.toHaveBeenCalled();
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
