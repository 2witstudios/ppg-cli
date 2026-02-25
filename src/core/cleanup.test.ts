import { describe, test, expect, vi, beforeEach } from 'vitest';
import type { WorktreeEntry } from '../types/manifest.js';
import type { PaneInfo } from './tmux.js';

// Mock dependencies before importing the module under test
vi.mock('./manifest.js', () => ({
  updateManifest: vi.fn(async (_root: string, updater: (m: any) => any) => {
    const manifest = {
      worktrees: {
        'wt-abc123': {
          id: 'wt-abc123',
          status: 'active',
        },
      },
    };
    return updater(manifest);
  }),
}));

vi.mock('./worktree.js', () => ({
  removeWorktree: vi.fn(async () => {}),
}));

vi.mock('./env.js', () => ({
  teardownWorktreeEnv: vi.fn(async () => {}),
}));

vi.mock('./tmux.js', () => ({
  killWindow: vi.fn(async () => {}),
}));

vi.mock('../lib/output.js', () => ({
  warn: vi.fn(),
}));

// Note: we do NOT mock ./self.js — we want real self-protection logic

import { cleanupWorktree } from './cleanup.js';
import { updateManifest } from './manifest.js';
import { removeWorktree } from './worktree.js';
import { teardownWorktreeEnv } from './env.js';
import * as tmux from './tmux.js';
import { warn } from '../lib/output.js';

function makePaneInfo(paneId: string): PaneInfo {
  return { paneId, panePid: '1234', currentCommand: 'claude', isDead: false };
}

function makeWorktree(overrides: Partial<WorktreeEntry> = {}): WorktreeEntry {
  return {
    id: 'wt-abc123',
    name: 'test-wt',
    path: '/tmp/wt',
    branch: 'ppg/test-wt',
    baseBranch: 'main',
    status: 'active',
    tmuxWindow: 'ppg:1',
    agents: {
      'ag-1': {
        id: 'ag-1',
        name: 'test',
        agentType: 'claude',
        status: 'running',
        tmuxTarget: 'ppg:1.0',
        prompt: 'test',
        resultFile: '/tmp/result.md',
        startedAt: new Date().toISOString(),
      },
    },
    createdAt: new Date().toISOString(),
    ...overrides,
  };
}

describe('cleanupWorktree', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test('updates manifest BEFORE killing tmux windows', async () => {
    const callOrder: string[] = [];
    vi.mocked(updateManifest).mockImplementation(async () => {
      callOrder.push('manifest');
      return {} as any;
    });
    vi.mocked(tmux.killWindow).mockImplementation(async () => {
      callOrder.push('tmux');
    });

    const wt = makeWorktree();
    await cleanupWorktree('/project', wt);

    expect(callOrder[0]).toBe('manifest');
    expect(callOrder.indexOf('tmux')).toBeGreaterThan(0);
  });

  test('kills tmux windows and removes worktree', async () => {
    const wt = makeWorktree();
    const result = await cleanupWorktree('/project', wt);

    expect(updateManifest).toHaveBeenCalled();
    expect(tmux.killWindow).toHaveBeenCalled();
    expect(teardownWorktreeEnv).toHaveBeenCalledWith(wt.path);
    expect(removeWorktree).toHaveBeenCalled();
    expect(result.manifestUpdated).toBe(true);
    expect(result.tmuxKilled).toBeGreaterThan(0);
  });

  test('self-protection skips tmux targets containing current process', async () => {
    const selfPaneId = '%5';
    const paneMap = new Map<string, PaneInfo>();
    paneMap.set('%5', makePaneInfo('%5'));
    paneMap.set('ppg:1', makePaneInfo('%5'));
    paneMap.set('ppg:1.0', makePaneInfo('%5'));

    const wt = makeWorktree();
    const result = await cleanupWorktree('/project', wt, { selfPaneId, paneMap });

    expect(result.selfProtected).toBe(true);
    expect(result.selfProtectedTargets.length).toBeGreaterThan(0);
    expect(result.tmuxKilled).toBe(0);
    expect(warn).toHaveBeenCalled();
  });

  test('idempotent: skips tmux kill when already cleaned', async () => {
    const wt = makeWorktree({ status: 'cleaned' });
    const result = await cleanupWorktree('/project', wt);

    expect(result.manifestUpdated).toBe(false);
    expect(tmux.killWindow).not.toHaveBeenCalled();
    // Still attempts filesystem cleanup
    expect(teardownWorktreeEnv).toHaveBeenCalled();
    expect(removeWorktree).toHaveBeenCalled();
  });

  test('handles tmux kill failures gracefully', async () => {
    vi.mocked(tmux.killWindow).mockRejectedValueOnce(new Error('tmux server crash'));

    const wt = makeWorktree();
    const result = await cleanupWorktree('/project', wt);

    expect(result.tmuxFailed).toBe(1);
    expect(warn).toHaveBeenCalled();
    // Should still continue with remaining cleanup
    expect(teardownWorktreeEnv).toHaveBeenCalled();
    expect(removeWorktree).toHaveBeenCalled();
  });

  test('deduplicates tmux targets', async () => {
    // Agent target and window target are the same
    const wt = makeWorktree({
      tmuxWindow: 'ppg:1',
      agents: {
        'ag-1': {
          id: 'ag-1',
          name: 'test',
          agentType: 'claude',
          status: 'running',
          tmuxTarget: 'ppg:1', // Same as tmuxWindow
          prompt: 'test',
          resultFile: '/tmp/result.md',
          startedAt: new Date().toISOString(),
        },
      },
    });

    await cleanupWorktree('/project', wt);

    // Should only kill once despite duplicate target
    expect(tmux.killWindow).toHaveBeenCalledTimes(1);
  });
});
