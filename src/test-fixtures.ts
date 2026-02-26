import type { AgentEntry, WorktreeEntry } from './types/manifest.js';
import type { PaneInfo } from './core/tmux.js';

export function makeAgent(overrides?: Partial<AgentEntry>): AgentEntry {
  return {
    id: 'ag-test1234',
    name: 'claude',
    agentType: 'claude',
    status: 'running',
    tmuxTarget: 'pogu:1.0',
    prompt: 'Do the thing',
    resultFile: '/tmp/project/.pogu/results/ag-test1234.md',
    startedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  };
}

export function makeWorktree(overrides?: Partial<WorktreeEntry>): WorktreeEntry {
  return {
    id: 'wt-abc123',
    name: 'feature-auth',
    path: '/tmp/project/.worktrees/wt-abc123',
    branch: 'pogu/feature-auth',
    baseBranch: 'main',
    status: 'active',
    tmuxWindow: 'pogu:1',
    agents: {},
    createdAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  };
}

export function makePaneInfo(overrides?: Partial<PaneInfo>): PaneInfo {
  return {
    paneId: '%42',
    panePid: '12345',
    currentCommand: 'claude',
    isDead: false,
    ...overrides,
  };
}
