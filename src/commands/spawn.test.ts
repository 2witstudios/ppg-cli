import { access } from 'node:fs/promises';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import { spawnCommand } from './spawn.js';
import { loadConfig, resolveAgentConfig } from '../core/config.js';
import { readManifest, resolveWorktree, updateManifest } from '../core/manifest.js';
import { spawnAgent } from '../core/agent.js';
import { getRepoRoot } from '../core/worktree.js';
import { agentId, sessionId } from '../lib/id.js';
import * as tmux from '../core/tmux.js';
import type { AgentEntry, Manifest } from '../types/manifest.js';

vi.mock('node:fs/promises', async () => {
  const actual = await vi.importActual<typeof import('node:fs/promises')>('node:fs/promises');
  const mockedAccess = vi.fn();
  return {
    ...actual,
    access: mockedAccess,
    default: {
      ...actual,
      access: mockedAccess,
    },
  };
});

vi.mock('../core/config.js', () => ({
  loadConfig: vi.fn(),
  resolveAgentConfig: vi.fn(),
}));

vi.mock('../core/manifest.js', () => ({
  readManifest: vi.fn(),
  updateManifest: vi.fn(),
  resolveWorktree: vi.fn(),
}));

vi.mock('../core/agent.js', () => ({
  spawnAgent: vi.fn(),
}));

vi.mock('../core/worktree.js', () => ({
  getRepoRoot: vi.fn(),
  getCurrentBranch: vi.fn(),
  createWorktree: vi.fn(),
  adoptWorktree: vi.fn(),
}));

vi.mock('../core/tmux.js', () => ({
  ensureSession: vi.fn(),
  createWindow: vi.fn(),
  splitPane: vi.fn(),
}));

vi.mock('../core/terminal.js', () => ({
  openTerminalWindow: vi.fn(),
}));

vi.mock('../lib/output.js', () => ({
  output: vi.fn(),
  success: vi.fn(),
  info: vi.fn(),
}));

vi.mock('../lib/id.js', () => ({
  worktreeId: vi.fn(),
  agentId: vi.fn(),
  sessionId: vi.fn(),
}));

const mockedAccess = vi.mocked(access);
const mockedLoadConfig = vi.mocked(loadConfig);
const mockedResolveAgentConfig = vi.mocked(resolveAgentConfig);
const mockedReadManifest = vi.mocked(readManifest);
const mockedUpdateManifest = vi.mocked(updateManifest);
const mockedResolveWorktree = vi.mocked(resolveWorktree);
const mockedSpawnAgent = vi.mocked(spawnAgent);
const mockedGetRepoRoot = vi.mocked(getRepoRoot);
const mockedAgentId = vi.mocked(agentId);
const mockedSessionId = vi.mocked(sessionId);
const mockedEnsureSession = vi.mocked(tmux.ensureSession);
const mockedCreateWindow = vi.mocked(tmux.createWindow);
const mockedSplitPane = vi.mocked(tmux.splitPane);

function createManifest(tmuxWindow = ''): Manifest {
  return {
    version: 1,
    projectRoot: '/tmp/repo',
    sessionName: 'ppg-test',
    worktrees: {
      wt1: {
        id: 'wt1',
        name: 'feature',
        path: '/tmp/repo/.ppg/worktrees/wt1',
        branch: 'ppg/feature',
        baseBranch: 'main',
        status: 'active',
        tmuxWindow,
        agents: {} as Record<string, AgentEntry>,
        createdAt: '2026-02-27T00:00:00.000Z',
      },
    },
    createdAt: '2026-02-27T00:00:00.000Z',
    updatedAt: '2026-02-27T00:00:00.000Z',
  };
}

describe('spawnCommand', () => {
  let manifestState: Manifest = createManifest();
  let nextAgent = 1;
  let nextSession = 1;

  beforeEach(() => {
    vi.clearAllMocks();
    manifestState = createManifest();
    nextAgent = 1;
    nextSession = 1;

    mockedAccess.mockResolvedValue(undefined);
    mockedGetRepoRoot.mockResolvedValue('/tmp/repo');
    mockedLoadConfig.mockResolvedValue({
      sessionName: 'ppg-test',
      defaultAgent: 'claude',
      agents: {
        claude: {
          name: 'claude',
          command: 'claude',
          interactive: true,
        },
      },
      envFiles: [],
      symlinkNodeModules: false,
    });
    mockedResolveAgentConfig.mockReturnValue({
      name: 'claude',
      command: 'claude',
      interactive: true,
    });
    mockedReadManifest.mockImplementation(async () => structuredClone(manifestState));
    mockedResolveWorktree.mockImplementation((manifest, ref) => (manifest as any).worktrees[ref as string]);
    mockedUpdateManifest.mockImplementation(async (_projectRoot, updater) => {
      manifestState = await updater(structuredClone(manifestState));
      return manifestState as any;
    });
    mockedAgentId.mockImplementation(() => `ag-${nextAgent++}`);
    mockedSessionId.mockImplementation(() => `session-${nextSession++}`);
    mockedSpawnAgent.mockImplementation(async (opts: any) => ({
      id: opts.agentId,
      name: opts.agentConfig.name,
      agentType: opts.agentConfig.name,
      status: 'running',
      tmuxTarget: opts.tmuxTarget,
      prompt: opts.prompt,
      startedAt: '2026-02-27T00:00:00.000Z',
      sessionId: opts.sessionId,
    }));
    mockedSplitPane.mockResolvedValue({ target: 'ppg-test:1.1' } as any);
  });

  test('given lazy tmux window and spawn failure, should persist tmux window before agent writes', async () => {
    mockedCreateWindow
      .mockResolvedValueOnce('ppg-test:7')
      .mockResolvedValueOnce('ppg-test:8');
    mockedSpawnAgent.mockRejectedValueOnce(new Error('spawn failed'));

    await expect(
      spawnCommand({
        worktree: 'wt1',
        prompt: 'Do work',
        count: 1,
      }),
    ).rejects.toThrow('spawn failed');

    expect(manifestState.worktrees.wt1.tmuxWindow).toBe('ppg-test:7');
    expect(Object.keys(manifestState.worktrees.wt1.agents)).toHaveLength(0);
    expect(mockedUpdateManifest).toHaveBeenCalledTimes(1);
    expect(mockedEnsureSession).toHaveBeenCalledTimes(1);
  });

  test('given existing worktree, should update manifest after each spawned agent', async () => {
    manifestState = createManifest('ppg-test:1');
    mockedCreateWindow
      .mockResolvedValueOnce('ppg-test:2')
      .mockResolvedValueOnce('ppg-test:3');

    await spawnCommand({
      worktree: 'wt1',
      prompt: 'Do work',
      count: 2,
    });

    expect(mockedUpdateManifest).toHaveBeenCalledTimes(2);
    expect(Object.keys(manifestState.worktrees.wt1.agents)).toEqual(['ag-1', 'ag-2']);
    expect(manifestState.worktrees.wt1.agents['ag-1'].tmuxTarget).toBe('ppg-test:2');
    expect(manifestState.worktrees.wt1.agents['ag-2'].tmuxTarget).toBe('ppg-test:3');
    expect(mockedEnsureSession).not.toHaveBeenCalled();
  });
});
