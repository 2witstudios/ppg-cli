import { describe, test, expect, beforeEach } from 'vitest';
import { getCurrentPaneId, wouldAffectSelf, excludeSelf, wouldCleanupAffectSelf } from './self.js';
import type { PaneInfo } from './tmux.js';
import type { AgentEntry, WorktreeEntry } from '../types/manifest.js';

function makePaneInfo(paneId: string): PaneInfo {
  return { paneId, panePid: '1234', currentCommand: 'claude', isDead: false };
}

function makeAgent(id: string, tmuxTarget: string): AgentEntry {
  return {
    id,
    name: 'test',
    agentType: 'claude',
    status: 'running',
    tmuxTarget,
    prompt: 'test',
    resultFile: '/tmp/result.md',
    startedAt: new Date().toISOString(),
  };
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
    agents: {},
    createdAt: new Date().toISOString(),
    ...overrides,
  };
}

describe('getCurrentPaneId', () => {
  const originalEnv = process.env.TMUX_PANE;

  beforeEach(() => {
    // Restore after each test
    if (originalEnv !== undefined) {
      process.env.TMUX_PANE = originalEnv;
    } else {
      delete process.env.TMUX_PANE;
    }
  });

  test('returns pane ID when TMUX_PANE is set', () => {
    process.env.TMUX_PANE = '%5';
    expect(getCurrentPaneId()).toBe('%5');
  });

  test('returns null when not in tmux', () => {
    delete process.env.TMUX_PANE;
    expect(getCurrentPaneId()).toBeNull();
  });
});

describe('wouldAffectSelf', () => {
  const selfPaneId = '%5';

  // Build a pane map simulating a session with two windows
  // Window 1 has panes %5 (self) and %6
  // Window 2 has pane %7
  const paneMap = new Map<string, PaneInfo>();

  // session:window.pane entries
  paneMap.set('ppg:1.0', makePaneInfo('%5'));
  paneMap.set('ppg:1.1', makePaneInfo('%6'));
  paneMap.set('ppg:2.0', makePaneInfo('%7'));

  // pane ID entries
  paneMap.set('%5', makePaneInfo('%5'));
  paneMap.set('%6', makePaneInfo('%6'));
  paneMap.set('%7', makePaneInfo('%7'));

  // window entries (first pane in window)
  paneMap.set('ppg:1', makePaneInfo('%5'));
  paneMap.set('ppg:2', makePaneInfo('%7'));

  test('direct pane ID match', () => {
    expect(wouldAffectSelf('%5', selfPaneId, paneMap)).toBe(true);
  });

  test('pane target resolves to self', () => {
    expect(wouldAffectSelf('ppg:1.0', selfPaneId, paneMap)).toBe(true);
  });

  test('window-level target containing self pane', () => {
    expect(wouldAffectSelf('ppg:1', selfPaneId, paneMap)).toBe(true);
  });

  test('different pane is safe', () => {
    expect(wouldAffectSelf('%7', selfPaneId, paneMap)).toBe(false);
  });

  test('different window is safe', () => {
    expect(wouldAffectSelf('ppg:2', selfPaneId, paneMap)).toBe(false);
  });

  test('pane in same window but different pane is safe', () => {
    expect(wouldAffectSelf('ppg:1.1', selfPaneId, paneMap)).toBe(false);
  });

  test('unknown target is safe', () => {
    expect(wouldAffectSelf('ppg:99', selfPaneId, paneMap)).toBe(false);
  });
});

describe('excludeSelf', () => {
  const selfPaneId = '%5';
  const paneMap = new Map<string, PaneInfo>();
  paneMap.set('%5', makePaneInfo('%5'));
  paneMap.set('%7', makePaneInfo('%7'));
  paneMap.set('ppg:1.0', makePaneInfo('%5'));
  paneMap.set('ppg:2.0', makePaneInfo('%7'));

  test('splits agents into safe and skipped', () => {
    const agents = [
      makeAgent('ag-self', '%5'),
      makeAgent('ag-other', '%7'),
    ];
    const { safe, skipped } = excludeSelf(agents, selfPaneId, paneMap);
    expect(safe).toHaveLength(1);
    expect(safe[0].id).toBe('ag-other');
    expect(skipped).toHaveLength(1);
    expect(skipped[0].id).toBe('ag-self');
  });

  test('all safe when no self match', () => {
    const agents = [makeAgent('ag-a', '%7')];
    const { safe, skipped } = excludeSelf(agents, selfPaneId, paneMap);
    expect(safe).toHaveLength(1);
    expect(skipped).toHaveLength(0);
  });

  test('empty input returns empty results', () => {
    const { safe, skipped } = excludeSelf([], selfPaneId, paneMap);
    expect(safe).toHaveLength(0);
    expect(skipped).toHaveLength(0);
  });
});

describe('wouldCleanupAffectSelf', () => {
  const selfPaneId = '%5';
  const paneMap = new Map<string, PaneInfo>();
  paneMap.set('%5', makePaneInfo('%5'));
  paneMap.set('%7', makePaneInfo('%7'));
  paneMap.set('ppg:1', makePaneInfo('%5'));
  paneMap.set('ppg:1.0', makePaneInfo('%5'));
  paneMap.set('ppg:2', makePaneInfo('%7'));
  paneMap.set('ppg:2.0', makePaneInfo('%7'));

  test('returns true if worktree tmuxWindow contains self', () => {
    const wt = makeWorktree({ tmuxWindow: 'ppg:1' });
    expect(wouldCleanupAffectSelf(wt, selfPaneId, paneMap)).toBe(true);
  });

  test('returns true if any agent target matches self', () => {
    const wt = makeWorktree({
      tmuxWindow: 'ppg:2',
      agents: { 'ag-1': makeAgent('ag-1', '%5') },
    });
    expect(wouldCleanupAffectSelf(wt, selfPaneId, paneMap)).toBe(true);
  });

  test('returns false when no overlap with self', () => {
    const wt = makeWorktree({
      tmuxWindow: 'ppg:2',
      agents: { 'ag-1': makeAgent('ag-1', '%7') },
    });
    expect(wouldCleanupAffectSelf(wt, selfPaneId, paneMap)).toBe(false);
  });

  test('returns false when worktree has no tmux window', () => {
    const wt = makeWorktree({ tmuxWindow: '' });
    expect(wouldCleanupAffectSelf(wt, selfPaneId, paneMap)).toBe(false);
  });
});
