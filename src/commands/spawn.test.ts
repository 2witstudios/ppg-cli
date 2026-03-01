import { describe, expect, test, vi, beforeEach } from 'vitest';
import { spawnCommand } from './spawn.js';
import { performSpawn } from '../core/operations/spawn.js';
import type { SpawnResult } from '../core/operations/spawn.js';
import type { AgentEntry } from '../types/manifest.js';

vi.mock('../core/operations/spawn.js', () => ({
  performSpawn: vi.fn(),
}));

vi.mock('../lib/output.js', () => ({
  output: vi.fn(),
  success: vi.fn(),
  info: vi.fn(),
}));

const mockedPerformSpawn = vi.mocked(performSpawn);
const { output, success, info } = await import('../lib/output.js');

function makeAgent(id: string, target: string): AgentEntry {
  return {
    id,
    name: 'claude',
    agentType: 'claude',
    status: 'running',
    tmuxTarget: target,
    prompt: 'Do work',
    startedAt: '2026-02-27T00:00:00.000Z',
    sessionId: 'session-1',
  };
}

function makeResult(overrides?: Partial<SpawnResult>): SpawnResult {
  return {
    worktree: {
      id: 'wt1',
      name: 'feature',
      branch: 'ppg/feature',
      path: '/tmp/repo/.worktrees/wt1',
      tmuxWindow: 'ppg-test:1',
    },
    agents: [makeAgent('ag-1', 'ppg-test:1')],
    ...overrides,
  };
}

describe('spawnCommand', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockedPerformSpawn.mockResolvedValue(makeResult());
  });

  test('given basic options, should call performSpawn and output success', async () => {
    await spawnCommand({ prompt: 'Do work', count: 1 });

    expect(mockedPerformSpawn).toHaveBeenCalledWith({ prompt: 'Do work', count: 1 });
    expect(success).toHaveBeenCalledWith(expect.stringContaining('Spawned worktree wt1'));
    expect(info).toHaveBeenCalledWith(expect.stringContaining('Agent ag-1'));
  });

  test('given json option, should output JSON', async () => {
    await spawnCommand({ prompt: 'Do work', count: 1, json: true });

    expect(output).toHaveBeenCalledWith(
      expect.objectContaining({ success: true, worktree: expect.objectContaining({ id: 'wt1' }) }),
      true,
    );
  });

  test('given worktree option, should show added message', async () => {
    await spawnCommand({ worktree: 'wt1', prompt: 'Do work', count: 1 });

    expect(success).toHaveBeenCalledWith(expect.stringContaining('Added 1 agent(s) to worktree'));
  });

  test('given performSpawn failure, should propagate error', async () => {
    mockedPerformSpawn.mockRejectedValueOnce(new Error('spawn failed'));

    await expect(
      spawnCommand({ prompt: 'Do work', count: 1 }),
    ).rejects.toThrow('spawn failed');
  });

  test('given multiple agents, should show all agents', async () => {
    mockedPerformSpawn.mockResolvedValue(makeResult({
      agents: [
        makeAgent('ag-1', 'ppg-test:1'),
        makeAgent('ag-2', 'ppg-test:2'),
      ],
    }));

    await spawnCommand({ prompt: 'Do work', count: 2 });

    expect(success).toHaveBeenCalledWith(expect.stringContaining('2 agent(s)'));
    expect(info).toHaveBeenCalledWith(expect.stringContaining('ag-1'));
    expect(info).toHaveBeenCalledWith(expect.stringContaining('ag-2'));
  });
});
