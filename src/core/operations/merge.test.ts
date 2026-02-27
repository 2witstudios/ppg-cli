import { describe, test, expect, vi, beforeEach } from 'vitest';
import type { Manifest, WorktreeEntry } from '../../types/manifest.js';

// --- Mocks ---

const mockExeca = vi.fn(async () => ({ stdout: 'main', stderr: '' }));
vi.mock('execa', () => ({
  execa: (...args: unknown[]) => (mockExeca as Function)(...args),
}));

const mockManifest = (): Manifest => ({
  version: 1,
  projectRoot: '/project',
  sessionName: 'ppg',
  worktrees: {
    'wt-abc123': makeWorktree(),
  },
  createdAt: '2025-01-01T00:00:00.000Z',
  updatedAt: '2025-01-01T00:00:00.000Z',
});

let latestManifest: Manifest;

vi.mock('../manifest.js', () => ({
  requireManifest: vi.fn(async () => latestManifest),
  updateManifest: vi.fn(async (_root: string, updater: (m: Manifest) => Manifest | Promise<Manifest>) => {
    latestManifest = await updater(latestManifest);
    return latestManifest;
  }),
  resolveWorktree: vi.fn((manifest: Manifest, ref: string) => {
    return manifest.worktrees[ref] ??
      Object.values(manifest.worktrees).find((wt) => wt.name === ref || wt.branch === ref);
  }),
}));

vi.mock('../agent.js', () => ({
  refreshAllAgentStatuses: vi.fn(async (m: Manifest) => m),
}));

vi.mock('../worktree.js', () => ({
  getCurrentBranch: vi.fn(async () => 'main'),
}));

vi.mock('../cleanup.js', () => ({
  cleanupWorktree: vi.fn(async () => ({
    worktreeId: 'wt-abc123',
    manifestUpdated: true,
    tmuxKilled: 1,
    tmuxSkipped: 0,
    tmuxFailed: 0,
    selfProtected: false,
    selfProtectedTargets: [],
  })),
}));

vi.mock('../self.js', () => ({
  getCurrentPaneId: vi.fn(() => null),
}));

vi.mock('../tmux.js', () => ({
  listSessionPanes: vi.fn(async () => new Map()),
}));

vi.mock('../../lib/env.js', () => ({
  execaEnv: { env: { PATH: '/usr/bin' } },
}));

import { performMerge } from './merge.js';
import { updateManifest } from '../manifest.js';
import { getCurrentBranch } from '../worktree.js';
import { cleanupWorktree } from '../cleanup.js';
import { getCurrentPaneId } from '../self.js';
import { listSessionPanes } from '../tmux.js';
import { PpgError, MergeFailedError, WorktreeNotFoundError } from '../../lib/errors.js';

function makeWorktree(overrides: Partial<WorktreeEntry> = {}): WorktreeEntry {
  return {
    id: 'wt-abc123',
    name: 'test-feature',
    path: '/project/.worktrees/wt-abc123',
    branch: 'ppg/test-feature',
    baseBranch: 'main',
    status: 'active',
    tmuxWindow: 'ppg:1',
    agents: {
      'ag-00000001': {
        id: 'ag-00000001',
        name: 'claude-1',
        agentType: 'claude',
        status: 'exited',
        tmuxTarget: 'ppg:1.0',
        prompt: 'do stuff',
        startedAt: '2025-01-01T00:00:00.000Z',
      },
    },
    createdAt: '2025-01-01T00:00:00.000Z',
    ...overrides,
  };
}

describe('performMerge', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    latestManifest = mockManifest();
    mockExeca.mockResolvedValue({ stdout: 'main', stderr: '' });
  });

  test('performs squash merge and returns result', async () => {
    const result = await performMerge({
      projectRoot: '/project',
      worktreeRef: 'wt-abc123',
      strategy: 'squash',
    });

    expect(result.merged).toBe(true);
    expect(result.strategy).toBe('squash');
    expect(result.worktreeId).toBe('wt-abc123');
    expect(result.branch).toBe('ppg/test-feature');
    expect(result.baseBranch).toBe('main');
    expect(result.cleaned).toBe(true);
    expect(result.dryRun).toBe(false);
  });

  test('defaults to squash strategy', async () => {
    const result = await performMerge({
      projectRoot: '/project',
      worktreeRef: 'wt-abc123',
    });

    expect(result.strategy).toBe('squash');
    // Verify git merge --squash was called
    expect(mockExeca).toHaveBeenCalledWith(
      'git', ['merge', '--squash', 'ppg/test-feature'],
      expect.objectContaining({ cwd: '/project' }),
    );
  });

  test('supports no-ff merge strategy', async () => {
    await performMerge({
      projectRoot: '/project',
      worktreeRef: 'wt-abc123',
      strategy: 'no-ff',
    });

    expect(mockExeca).toHaveBeenCalledWith(
      'git', ['merge', '--no-ff', 'ppg/test-feature', '-m', 'ppg: merge test-feature (ppg/test-feature)'],
      expect.objectContaining({ cwd: '/project' }),
    );
  });

  test('state transitions: active → merging → merged → cleaned', async () => {
    const statusLog: string[] = [];
    vi.mocked(updateManifest).mockImplementation(async (_root, updater) => {
      latestManifest = await updater(latestManifest);
      const wt = latestManifest.worktrees['wt-abc123'];
      if (wt) statusLog.push(wt.status);
      return latestManifest;
    });

    await performMerge({
      projectRoot: '/project',
      worktreeRef: 'wt-abc123',
    });

    // Call order: refreshAllAgentStatuses (active) → set merging → set merged
    // Note: cleanup's manifest update is mocked, so 'cleaned' is not tracked here
    expect(statusLog).toContain('merging');
    expect(statusLog).toContain('merged');
    expect(statusLog.indexOf('merging')).toBeLessThan(statusLog.indexOf('merged'));
  });

  test('sets status to failed on git merge error', async () => {
    mockExeca.mockImplementation(async (...args: unknown[]) => {
      const cmdArgs = args[1] as string[];
      if (cmdArgs[0] === 'merge') {
        throw new Error('CONFLICT (content): Merge conflict in file.ts');
      }
      return { stdout: 'main', stderr: '' };
    });

    await expect(
      performMerge({
        projectRoot: '/project',
        worktreeRef: 'wt-abc123',
      }),
    ).rejects.toThrow(MergeFailedError);

    expect(latestManifest.worktrees['wt-abc123'].status).toBe('failed');
  });

  test('throws AGENTS_RUNNING when agents still running', async () => {
    latestManifest.worktrees['wt-abc123'].agents['ag-00000001'].status = 'running';

    const err = await performMerge({
      projectRoot: '/project',
      worktreeRef: 'wt-abc123',
    }).catch((e) => e);

    expect(err).toBeInstanceOf(PpgError);
    expect(err.code).toBe('AGENTS_RUNNING');
  });

  test('force bypasses running agent check', async () => {
    latestManifest.worktrees['wt-abc123'].agents['ag-00000001'].status = 'running';

    const result = await performMerge({
      projectRoot: '/project',
      worktreeRef: 'wt-abc123',
      force: true,
    });

    expect(result.merged).toBe(true);
  });

  test('throws WorktreeNotFoundError for invalid ref', async () => {
    await expect(
      performMerge({
        projectRoot: '/project',
        worktreeRef: 'wt-nonexistent',
      }),
    ).rejects.toThrow(WorktreeNotFoundError);
  });

  test('dry run returns early without modifying state', async () => {
    const result = await performMerge({
      projectRoot: '/project',
      worktreeRef: 'wt-abc123',
      dryRun: true,
    });

    expect(result.dryRun).toBe(true);
    expect(result.merged).toBe(false);
    expect(result.cleaned).toBe(false);
    // Should not have called git merge
    expect(mockExeca).not.toHaveBeenCalledWith(
      'git', expect.arrayContaining(['merge']),
      expect.anything(),
    );
    // Worktree status unchanged
    expect(latestManifest.worktrees['wt-abc123'].status).toBe('active');
  });

  test('skips cleanup when cleanup=false', async () => {
    const result = await performMerge({
      projectRoot: '/project',
      worktreeRef: 'wt-abc123',
      cleanup: false,
    });

    expect(result.merged).toBe(true);
    expect(result.cleaned).toBe(false);
    expect(cleanupWorktree).not.toHaveBeenCalled();
  });

  test('switches to base branch if not already on it', async () => {
    vi.mocked(getCurrentBranch).mockResolvedValueOnce('some-other-branch');

    await performMerge({
      projectRoot: '/project',
      worktreeRef: 'wt-abc123',
    });

    expect(mockExeca).toHaveBeenCalledWith(
      'git', ['checkout', 'main'],
      expect.objectContaining({ cwd: '/project' }),
    );
  });

  test('skips checkout when already on base branch', async () => {
    vi.mocked(getCurrentBranch).mockResolvedValueOnce('main');

    await performMerge({
      projectRoot: '/project',
      worktreeRef: 'wt-abc123',
    });

    expect(mockExeca).not.toHaveBeenCalledWith(
      'git', ['checkout', 'main'],
      expect.anything(),
    );
  });

  test('passes self-protection context to cleanup', async () => {
    vi.mocked(getCurrentPaneId).mockReturnValueOnce('%5');
    const paneMap = new Map();
    vi.mocked(listSessionPanes).mockResolvedValueOnce(paneMap);

    await performMerge({
      projectRoot: '/project',
      worktreeRef: 'wt-abc123',
    });

    expect(listSessionPanes).toHaveBeenCalledWith('ppg');
    expect(cleanupWorktree).toHaveBeenCalledWith(
      '/project',
      expect.objectContaining({ id: 'wt-abc123' }),
      { selfPaneId: '%5', paneMap },
    );
  });

  test('reports selfProtected when cleanup skips targets', async () => {
    vi.mocked(cleanupWorktree).mockResolvedValueOnce({
      worktreeId: 'wt-abc123',
      manifestUpdated: true,
      tmuxKilled: 0,
      tmuxSkipped: 0,
      tmuxFailed: 0,
      selfProtected: true,
      selfProtectedTargets: ['ppg:1'],
    });

    const result = await performMerge({
      projectRoot: '/project',
      worktreeRef: 'wt-abc123',
    });

    expect(result.selfProtected).toBe(true);
  });

  test('sets mergedAt timestamp on successful merge', async () => {
    await performMerge({
      projectRoot: '/project',
      worktreeRef: 'wt-abc123',
    });

    expect(latestManifest.worktrees['wt-abc123'].mergedAt).toBeDefined();
    // Should be a valid ISO date
    expect(() => new Date(latestManifest.worktrees['wt-abc123'].mergedAt!)).not.toThrow();
  });
});
