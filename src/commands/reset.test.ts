import { describe, test, expect } from 'vitest';
import type { WorktreeEntry, AgentEntry } from '../types/manifest.js';
import { findAtRiskWorktrees } from './reset.js';

function makeAgent(overrides: Partial<AgentEntry> = {}): AgentEntry {
  return {
    id: 'ag-test1234',
    name: 'claude',
    agentType: 'claude',
    status: 'running',
    tmuxTarget: 'ppg:1.0',
    prompt: 'test prompt',
    startedAt: new Date().toISOString(),
    ...overrides,
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

  test('given worktree with idle agent, should flag as at-risk', () => {
    const wt = makeWorktree({
      agents: { 'ag-1': makeAgent({ id: 'ag-1', status: 'idle' }) },
    });

    const result = findAtRiskWorktrees([wt]);

    expect(result).toHaveLength(1);
    expect(result[0].id).toBe('wt-abc123');
  });

  test('given worktree with exited agent, should flag as at-risk', () => {
    const wt = makeWorktree({
      agents: { 'ag-1': makeAgent({ id: 'ag-1', status: 'exited' }) },
    });

    const result = findAtRiskWorktrees([wt]);

    expect(result).toHaveLength(1);
    expect(result[0].id).toBe('wt-abc123');
  });

  test('given worktree already merged, should not flag', () => {
    const wt = makeWorktree({
      status: 'merged',
      agents: { 'ag-1': makeAgent({ id: 'ag-1', status: 'idle' }) },
    });

    expect(findAtRiskWorktrees([wt])).toHaveLength(0);
  });

  test('given worktree already cleaned, should not flag', () => {
    const wt = makeWorktree({
      status: 'cleaned',
      agents: { 'ag-1': makeAgent({ id: 'ag-1', status: 'idle' }) },
    });

    expect(findAtRiskWorktrees([wt])).toHaveLength(0);
  });

  test('given worktree with prUrl, should not flag', () => {
    const wt = makeWorktree({
      prUrl: 'https://github.com/user/repo/pull/42',
      agents: { 'ag-1': makeAgent({ id: 'ag-1', status: 'idle' }) },
    });

    expect(findAtRiskWorktrees([wt])).toHaveLength(0);
  });

  test('given worktree with only running agents, should not flag', () => {
    const wt = makeWorktree({
      agents: { 'ag-1': makeAgent({ id: 'ag-1', status: 'running' }) },
    });

    expect(findAtRiskWorktrees([wt])).toHaveLength(0);
  });

  test('given worktree with only gone agents, should not flag', () => {
    const wt = makeWorktree({
      agents: { 'ag-1': makeAgent({ id: 'ag-1', status: 'gone' }) },
    });

    expect(findAtRiskWorktrees([wt])).toHaveLength(0);
  });

  test('given mixed: one idle + one gone agent, should flag (idle work exists)', () => {
    const wt = makeWorktree({
      agents: {
        'ag-1': makeAgent({ id: 'ag-1', status: 'idle' }),
        'ag-2': makeAgent({ id: 'ag-2', status: 'gone' }),
      },
    });

    expect(findAtRiskWorktrees([wt])).toHaveLength(1);
  });

  test('given multiple worktrees with mixed states, should only flag at-risk ones', () => {
    const wtAtRisk = makeWorktree({
      id: 'wt-risk',
      name: 'risky',
      agents: { 'ag-1': makeAgent({ id: 'ag-1', status: 'idle' }) },
    });
    const wtMerged = makeWorktree({
      id: 'wt-merged',
      name: 'merged',
      status: 'merged',
      agents: { 'ag-2': makeAgent({ id: 'ag-2', status: 'idle' }) },
    });
    const wtPRd = makeWorktree({
      id: 'wt-prd',
      name: 'prd',
      prUrl: 'https://github.com/user/repo/pull/1',
      agents: { 'ag-3': makeAgent({ id: 'ag-3', status: 'idle' }) },
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

  test('given failed worktree status with exited agent, should flag', () => {
    const wt = makeWorktree({
      status: 'failed',
      agents: { 'ag-1': makeAgent({ id: 'ag-1', status: 'exited' }) },
    });

    expect(findAtRiskWorktrees([wt])).toHaveLength(1);
  });
});
