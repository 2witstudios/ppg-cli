import { describe, test, expect, vi, beforeEach } from 'vitest';
import { access } from 'node:fs/promises';
import { execa } from 'execa';

vi.mock('node:fs/promises', async () => {
  const actual = await vi.importActual<typeof import('node:fs/promises')>('node:fs/promises');
  return { ...actual, access: vi.fn() };
});

vi.mock('execa', () => ({
  execa: vi.fn(),
}));

vi.mock('../core/worktree.js', () => ({
  getRepoRoot: vi.fn().mockResolvedValue('/tmp/test'),
}));

vi.mock('../core/manifest.js', () => ({
  readManifest: vi.fn(),
}));

vi.mock('../lib/output.js', () => ({
  info: vi.fn(),
}));

const mockedAccess = vi.mocked(access);
const mockedExeca = vi.mocked(execa);

describe('findDashboardBinary', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test('given local build exists, should return local build path', async () => {
    mockedAccess.mockResolvedValueOnce(undefined);
    const { findDashboardBinary } = await import('./ui.js');
    const result = await findDashboardBinary('/tmp/test');
    expect(result).toContain('PPG CLI/build/Build/Products/Release/PPG CLI.app');
  });

  test('given local build missing, should fall through to /Applications', async () => {
    mockedAccess
      .mockRejectedValueOnce(new Error('not found')) // local
      .mockResolvedValueOnce(undefined); // /Applications
    const { findDashboardBinary } = await import('./ui.js');
    const result = await findDashboardBinary('/tmp/test');
    expect(result).toBe('/Applications/PPG CLI.app/Contents/MacOS/PPG CLI');
  });

  test('given neither file exists, should fall through to Spotlight', async () => {
    mockedAccess
      .mockRejectedValueOnce(new Error('not found')) // local
      .mockRejectedValueOnce(new Error('not found')) // /Applications
      .mockResolvedValueOnce(undefined); // Spotlight result
    mockedExeca.mockResolvedValueOnce({
      stdout: '/Users/test/PPG CLI.app',
    } as any);
    const { findDashboardBinary } = await import('./ui.js');
    const result = await findDashboardBinary('/tmp/test');
    expect(result).toBe('/Users/test/PPG CLI.app/Contents/MacOS/PPG CLI');
  });

  test('given nothing found, should return null', async () => {
    mockedAccess.mockRejectedValue(new Error('not found'));
    mockedExeca.mockResolvedValueOnce({ stdout: '' } as any);
    const { findDashboardBinary } = await import('./ui.js');
    const result = await findDashboardBinary('/tmp/test');
    expect(result).toBeNull();
  });
});

describe('uiCommand', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test('given no manifest, should throw NotInitializedError', async () => {
    const { readManifest } = await import('../core/manifest.js');
    vi.mocked(readManifest).mockRejectedValueOnce(new Error('ENOENT'));

    const { uiCommand } = await import('./ui.js');
    await expect(uiCommand()).rejects.toThrow('not initialized');
  });

  test('given no binary found, should throw descriptive error', async () => {
    const { readManifest } = await import('../core/manifest.js');
    vi.mocked(readManifest).mockResolvedValueOnce({
      version: 1,
      projectRoot: '/tmp/test',
      sessionName: 'ppg-test',
      agents: {},
      worktrees: {},
      createdAt: '',
      updatedAt: '',
    });
    mockedAccess.mockRejectedValue(new Error('not found'));
    mockedExeca.mockResolvedValueOnce({ stdout: '' } as any);

    const { uiCommand } = await import('./ui.js');
    await expect(uiCommand()).rejects.toThrow('Dashboard app not found');
  });

  test('given binary found, should pass --project-root to launched process', async () => {
    const { readManifest } = await import('../core/manifest.js');
    vi.mocked(readManifest).mockResolvedValueOnce({
      version: 1,
      projectRoot: '/tmp/test',
      sessionName: 'ppg-test',
      agents: {},
      worktrees: {},
      createdAt: '',
      updatedAt: '',
    });
    // Local build exists
    mockedAccess.mockResolvedValueOnce(undefined);
    const mockProc = { unref: vi.fn() };
    mockedExeca.mockReturnValueOnce(mockProc as any);

    const { uiCommand } = await import('./ui.js');
    await uiCommand();

    expect(mockedExeca).toHaveBeenCalledWith(
      expect.any(String),
      expect.arrayContaining(['--project-root', '/tmp/test']),
      expect.any(Object),
    );
  });
});
