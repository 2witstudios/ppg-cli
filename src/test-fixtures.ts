import type { AgentEntry, Manifest, WorktreeEntry } from './types/manifest.js';
import type { PaneInfo } from './core/process-manager.js';

export function makeAgent(overrides?: Partial<AgentEntry>): AgentEntry {
  return {
    id: 'ag-test1234',
    name: 'claude',
    agentType: 'claude',
    status: 'running',
    tmuxTarget: 'ppg:1.0',
    prompt: 'Do the thing',
    startedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  };
}

export function makeWorktree(overrides?: Partial<WorktreeEntry>): WorktreeEntry {
  return {
    id: 'wt-abc123',
    name: 'feature-auth',
    path: '/tmp/project/.worktrees/wt-abc123',
    branch: 'ppg/feature-auth',
    baseBranch: 'main',
    status: 'active',
    tmuxWindow: 'ppg:1',
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

export function makeManifest(overrides?: Partial<Manifest>): Manifest {
  return {
    version: 1,
    projectRoot: '/tmp/project',
    sessionName: 'ppg',
    worktrees: {},
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  };
}
