import { describe, test, expect } from 'vitest';
import type { WorktreeEntry, AgentEntry } from '../types/manifest.js';
import { findAtRiskWorktrees } from './reset.js';

function makeAgent(overrides: Partial<AgentEntry> = {}): AgentEntry {
  return {
    id: 'ag-test1234',
    name: 'claude',
    agentType: 'claude',
    status: 'running',
    tmuxTarget: 'pogu:1.0',
    prompt: 'test prompt',
    resultFile: '/tmp/results/ag-test1234.md',
    startedAt: new Date().toISOString(),
    ...overrides,
  };
}

function makeWorktree(overrides: Partial<WorktreeEntry> = {}): WorktreeEntry {
  return {
    id: 'wt-abc123',
    name: 'test-wt',
    path: '/tmp/wt',
    branch: 'pogu/test-wt',
    baseBranch: 'main',
    status: 'active',
    tmuxWindow: 'pogu:1',
    agents: {
      'ag-test1234': makeAgent(),
    },
    createdAt: new Date().toISOString(),
    ...overrides,
  };
}

describe('findAtRiskWorktrees', () => {
  test('given empty list, should return empty', () => {
    expect(findAtRiskWorktrees([])).toEqual([]);
  });

  test('given worktree with completed agent, should flag as at-risk', () => {
    const wt = makeWorktree({
      agents: { 'ag-1': makeAgent({ id: 'ag-1', status: 'completed' }) },
    });

    const result = findAtRiskWorktrees([wt]);

    expect(result).toHaveLength(1);
    expect(result[0].id).toBe('wt-abc123');
  });

  test('given worktree already merged, should not flag', () => {
    const wt = makeWorktree({
      status: 'merged',
      agents: { 'ag-1': makeAgent({ id: 'ag-1', status: 'completed' }) },
    });

    expect(findAtRiskWorktrees([wt])).toHaveLength(0);
  });

  test('given worktree already cleaned, should not flag', () => {
    const wt = makeWorktree({
      status: 'cleaned',
      agents: { 'ag-1': makeAgent({ id: 'ag-1', status: 'completed' }) },
    });

    expect(findAtRiskWorktrees([wt])).toHaveLength(0);
  });

  test('given worktree with prUrl, should not flag', () => {
    const wt = makeWorktree({
      prUrl: 'https://github.com/user/repo/pull/42',
      agents: { 'ag-1': makeAgent({ id: 'ag-1', status: 'completed' }) },
    });

    expect(findAtRiskWorktrees([wt])).toHaveLength(0);
  });

  test('given worktree with only running agents (no completed), should not flag', () => {
    const wt = makeWorktree({
      agents: { 'ag-1': makeAgent({ id: 'ag-1', status: 'running' }) },
    });

    expect(findAtRiskWorktrees([wt])).toHaveLength(0);
  });

  test('given worktree with only failed agents, should not flag', () => {
    const wt = makeWorktree({
      agents: { 'ag-1': makeAgent({ id: 'ag-1', status: 'failed' }) },
    });

    expect(findAtRiskWorktrees([wt])).toHaveLength(0);
  });

  test('given worktree with only killed agents, should not flag', () => {
    const wt = makeWorktree({
      agents: { 'ag-1': makeAgent({ id: 'ag-1', status: 'killed' }) },
    });

    expect(findAtRiskWorktrees([wt])).toHaveLength(0);
  });

  test('given mixed: one completed + one failed agent, should flag (completed work exists)', () => {
    const wt = makeWorktree({
      agents: {
        'ag-1': makeAgent({ id: 'ag-1', status: 'completed' }),
        'ag-2': makeAgent({ id: 'ag-2', status: 'failed' }),
      },
    });

    expect(findAtRiskWorktrees([wt])).toHaveLength(1);
  });

  test('given multiple worktrees with mixed states, should only flag at-risk ones', () => {
    const wtAtRisk = makeWorktree({
      id: 'wt-risk',
      name: 'risky',
      agents: { 'ag-1': makeAgent({ id: 'ag-1', status: 'completed' }) },
    });
    const wtMerged = makeWorktree({
      id: 'wt-merged',
      name: 'merged',
      status: 'merged',
      agents: { 'ag-2': makeAgent({ id: 'ag-2', status: 'completed' }) },
    });
    const wtPRd = makeWorktree({
      id: 'wt-prd',
      name: 'prd',
      prUrl: 'https://github.com/user/repo/pull/1',
      agents: { 'ag-3': makeAgent({ id: 'ag-3', status: 'completed' }) },
    });
    const wtRunning = makeWorktree({
      id: 'wt-running',
      name: 'running',
      agents: { 'ag-4': makeAgent({ id: 'ag-4', status: 'running' }) },
    });

    const result = findAtRiskWorktrees([wtAtRisk, wtMerged, wtPRd, wtRunning]);

    expect(result).toHaveLength(1);
    expect(result[0].id).toBe('wt-risk');
  });

  test('given failed worktree status with completed agent, should flag', () => {
    const wt = makeWorktree({
      status: 'failed',
      agents: { 'ag-1': makeAgent({ id: 'ag-1', status: 'completed' }) },
    });

    expect(findAtRiskWorktrees([wt])).toHaveLength(1);
  });
});
