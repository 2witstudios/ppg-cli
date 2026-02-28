import { describe, test, expect, vi, beforeEach } from 'vitest';
import { makeWorktree, makeAgent } from '../test-fixtures.js';
import type { Manifest } from '../types/manifest.js';

// ---- Mocks ----

let manifestState: Manifest;

vi.mock('./manifest.js', () => ({
  updateManifest: vi.fn(async (_root: string, updater: (m: Manifest) => Manifest | Promise<Manifest>) => {
    manifestState = await updater(structuredClone(manifestState));
    return manifestState;
  }),
}));

vi.mock('./agent.js', () => ({
  killAgents: vi.fn(),
}));

// ---- Imports (after mocks) ----

import { killWorktreeAgents } from './kill.js';
import { killAgents } from './agent.js';

describe('killWorktreeAgents', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test('given worktree with running agents, should kill running agents and set status to gone', async () => {
    const agent1 = makeAgent({ id: 'ag-run00001', status: 'running' });
    const agent2 = makeAgent({ id: 'ag-idle0001', status: 'idle' });
    const wt = makeWorktree({
      id: 'wt-abc123',
      agents: { 'ag-run00001': agent1, 'ag-idle0001': agent2 },
    });
    manifestState = {
      version: 1,
      projectRoot: '/tmp/project',
      sessionName: 'ppg',
      agents: {},
      worktrees: { 'wt-abc123': structuredClone(wt) },
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    };

    const result = await killWorktreeAgents('/tmp/project', wt);

    expect(result.killed).toEqual(['ag-run00001']);
    expect(vi.mocked(killAgents)).toHaveBeenCalledWith([agent1]);
    expect(manifestState.worktrees['wt-abc123'].agents['ag-run00001'].status).toBe('gone');
    expect(manifestState.worktrees['wt-abc123'].agents['ag-idle0001'].status).toBe('idle');
  });

  test('given worktree with no running agents, should return empty killed list', async () => {
    const agent = makeAgent({ id: 'ag-done0001', status: 'exited' });
    const wt = makeWorktree({
      id: 'wt-abc123',
      agents: { 'ag-done0001': agent },
    });
    manifestState = {
      version: 1,
      projectRoot: '/tmp/project',
      sessionName: 'ppg',
      agents: {},
      worktrees: { 'wt-abc123': structuredClone(wt) },
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    };

    const result = await killWorktreeAgents('/tmp/project', wt);

    expect(result.killed).toEqual([]);
    expect(vi.mocked(killAgents)).toHaveBeenCalledWith([]);
  });
});
