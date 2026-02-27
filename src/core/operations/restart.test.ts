import { describe, test, expect, vi, beforeEach } from 'vitest';
import { makeAgent, makeWorktree } from '../../test-fixtures.js';
import type { Manifest } from '../../types/manifest.js';

// Mock node:fs/promises
vi.mock('node:fs/promises', () => ({
  default: {
    readFile: vi.fn(),
    mkdir: vi.fn(),
    writeFile: vi.fn(),
  },
}));

// Mock core modules
vi.mock('../worktree.js', () => ({
  getRepoRoot: vi.fn().mockResolvedValue('/tmp/project'),
}));

vi.mock('../config.js', () => ({
  loadConfig: vi.fn().mockResolvedValue({
    sessionName: 'ppg',
    defaultAgent: 'claude',
    agents: {
      claude: { name: 'claude', command: 'claude --dangerously-skip-permissions', interactive: true },
    },
  }),
  resolveAgentConfig: vi.fn().mockReturnValue({
    name: 'claude',
    command: 'claude --dangerously-skip-permissions',
    interactive: true,
  }),
}));

vi.mock('../manifest.js', () => ({
  requireManifest: vi.fn(),
  updateManifest: vi.fn(),
  findAgent: vi.fn(),
}));

vi.mock('../agent.js', () => ({
  spawnAgent: vi.fn(),
  killAgent: vi.fn(),
}));

vi.mock('../tmux.js', () => ({
  ensureSession: vi.fn(),
  createWindow: vi.fn(),
}));

vi.mock('../template.js', () => ({
  renderTemplate: vi.fn((_content: string, _ctx: unknown) => 'rendered prompt'),
}));

vi.mock('../../lib/id.js', () => ({
  agentId: vi.fn().mockReturnValue('ag-newagent'),
  sessionId: vi.fn().mockReturnValue('sess-new123'),
}));

vi.mock('../../lib/paths.js', () => ({
  agentPromptFile: vi.fn().mockReturnValue('/tmp/project/.ppg/agent-prompts/ag-test1234.md'),
}));

vi.mock('../../lib/errors.js', async () => {
  const actual = await vi.importActual('../../lib/errors.js');
  return actual;
});

import fs from 'node:fs/promises';
import { requireManifest, updateManifest, findAgent } from '../manifest.js';
import { spawnAgent, killAgent } from '../agent.js';
import * as tmux from '../tmux.js';
import { performRestart } from './restart.js';

const mockedFindAgent = vi.mocked(findAgent);
const mockedRequireManifest = vi.mocked(requireManifest);
const mockedUpdateManifest = vi.mocked(updateManifest);
const mockedSpawnAgent = vi.mocked(spawnAgent);
const mockedKillAgent = vi.mocked(killAgent);
const mockedEnsureSession = vi.mocked(tmux.ensureSession);
const mockedCreateWindow = vi.mocked(tmux.createWindow);
const mockedReadFile = vi.mocked(fs.readFile);

const PROJECT_ROOT = '/tmp/project';

function makeManifest(overrides?: Partial<Manifest>): Manifest {
  return {
    version: 1,
    projectRoot: PROJECT_ROOT,
    sessionName: 'ppg',
    worktrees: {},
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe('performRestart', () => {
  const oldAgent = makeAgent({ id: 'ag-oldagent', status: 'running' });
  const wt = makeWorktree({
    id: 'wt-abc123',
    name: 'feature-auth',
    agents: { 'ag-oldagent': oldAgent },
  });

  function setupDefaults() {
    const manifest = makeManifest({ worktrees: { [wt.id]: wt } });
    mockedRequireManifest.mockResolvedValue(manifest);
    mockedFindAgent.mockReturnValue({ worktree: wt, agent: oldAgent });
    mockedCreateWindow.mockResolvedValue('ppg:2');
    mockedReadFile.mockResolvedValue('original prompt' as never);
    mockedSpawnAgent.mockResolvedValue(makeAgent({
      id: 'ag-newagent',
      tmuxTarget: 'ppg:2',
      sessionId: 'sess-new123',
    }));
    mockedUpdateManifest.mockImplementation(async (_root, updater) => {
      const m = JSON.parse(JSON.stringify(manifest)) as Manifest;
      return updater(m);
    });
  }

  test('given running agent, should kill old agent before restarting', async () => {
    setupDefaults();

    await performRestart({ agentRef: 'ag-oldagent' });

    expect(mockedKillAgent).toHaveBeenCalledWith(oldAgent);
  });

  test('given idle agent, should not kill old agent', async () => {
    const idleAgent = makeAgent({ id: 'ag-oldagent', status: 'idle' });
    const idleWt = makeWorktree({
      id: 'wt-abc123',
      name: 'feature-auth',
      agents: { 'ag-oldagent': idleAgent },
    });
    const manifest = makeManifest({ worktrees: { [idleWt.id]: idleWt } });
    mockedRequireManifest.mockResolvedValue(manifest);
    mockedFindAgent.mockReturnValue({ worktree: idleWt, agent: idleAgent });
    mockedCreateWindow.mockResolvedValue('ppg:2');
    mockedReadFile.mockResolvedValue('original prompt' as never);
    mockedSpawnAgent.mockResolvedValue(makeAgent({ id: 'ag-newagent', tmuxTarget: 'ppg:2' }));
    mockedUpdateManifest.mockImplementation(async (_root, updater) => {
      const m = JSON.parse(JSON.stringify(manifest)) as Manifest;
      return updater(m);
    });

    await performRestart({ agentRef: 'ag-oldagent' });

    expect(mockedKillAgent).not.toHaveBeenCalled();
  });

  test('should create tmux window in same worktree', async () => {
    setupDefaults();

    await performRestart({ agentRef: 'ag-oldagent' });

    expect(mockedEnsureSession).toHaveBeenCalledWith('ppg');
    expect(mockedCreateWindow).toHaveBeenCalledWith('ppg', 'feature-auth-restart', wt.path);
  });

  test('should update manifest with new agent and mark old as gone', async () => {
    setupDefaults();

    await performRestart({ agentRef: 'ag-oldagent' });

    expect(mockedUpdateManifest).toHaveBeenCalledWith(PROJECT_ROOT, expect.any(Function));

    // Verify the updater function marks old agent gone and adds new agent
    const updater = mockedUpdateManifest.mock.calls[0][1];
    const testManifest = makeManifest({
      worktrees: {
        [wt.id]: {
          ...wt,
          agents: {
            'ag-oldagent': makeAgent({ id: 'ag-oldagent', status: 'running' }),
          },
        },
      },
    });
    const updated = await updater(testManifest);
    const updatedWt = updated.worktrees[wt.id];

    expect(updatedWt.agents['ag-oldagent'].status).toBe('gone');
    expect(updatedWt.agents['ag-newagent']).toBeDefined();
  });

  test('should return old and new agent info', async () => {
    setupDefaults();

    const result = await performRestart({ agentRef: 'ag-oldagent' });

    expect(result.oldAgentId).toBe('ag-oldagent');
    expect(result.newAgent.id).toBe('ag-newagent');
    expect(result.newAgent.tmuxTarget).toBe('ppg:2');
    expect(result.newAgent.sessionId).toBe('sess-new123');
    expect(result.newAgent.worktreeId).toBe('wt-abc123');
    expect(result.newAgent.worktreeName).toBe('feature-auth');
  });

  test('given prompt override, should use it instead of reading file', async () => {
    setupDefaults();

    await performRestart({ agentRef: 'ag-oldagent', prompt: 'custom prompt' });

    expect(mockedReadFile).not.toHaveBeenCalled();
  });

  test('given no prompt and missing prompt file, should throw PROMPT_NOT_FOUND', async () => {
    setupDefaults();
    mockedReadFile.mockRejectedValue(new Error('ENOENT'));

    await expect(performRestart({ agentRef: 'ag-oldagent' })).rejects.toThrow('Could not read original prompt');
  });

  test('given unknown agent ref, should throw AgentNotFoundError', async () => {
    const manifest = makeManifest();
    mockedRequireManifest.mockResolvedValue(manifest);
    mockedFindAgent.mockReturnValue(undefined);

    await expect(performRestart({ agentRef: 'ag-nonexist' })).rejects.toThrow('Agent not found');
  });
});
