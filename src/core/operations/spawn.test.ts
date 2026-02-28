import { describe, test, expect, vi, beforeEach } from 'vitest';
import type { Manifest, WorktreeEntry } from '../../types/manifest.js';
import type { Config } from '../../types/config.js';

// --- Mocks ---

vi.mock('node:fs/promises', () => ({
  default: {
    access: vi.fn(),
    readFile: vi.fn(),
    mkdir: vi.fn(),
    writeFile: vi.fn(),
  },
}));

vi.mock('../config.js', () => ({
  loadConfig: vi.fn(),
  resolveAgentConfig: vi.fn(),
}));

vi.mock('../manifest.js', () => ({
  readManifest: vi.fn(),
  updateManifest: vi.fn(),
  resolveWorktree: vi.fn(),
}));

vi.mock('../worktree.js', () => ({
  getRepoRoot: vi.fn(),
  getCurrentBranch: vi.fn(),
  createWorktree: vi.fn(),
  adoptWorktree: vi.fn(),
}));

vi.mock('../env.js', () => ({
  setupWorktreeEnv: vi.fn(),
}));

vi.mock('../template.js', () => ({
  loadTemplate: vi.fn(),
  renderTemplate: vi.fn((content: string) => content),
}));

vi.mock('../agent.js', () => ({
  spawnAgent: vi.fn(),
}));

vi.mock('../tmux.js', () => ({
  ensureSession: vi.fn(),
  createWindow: vi.fn(),
  splitPane: vi.fn(),
  sendKeys: vi.fn(),
}));

vi.mock('../terminal.js', () => ({
  openTerminalWindow: vi.fn(),
}));

vi.mock('../../lib/id.js', () => ({
  worktreeId: vi.fn(),
  agentId: vi.fn(),
  sessionId: vi.fn(),
}));

vi.mock('../../lib/paths.js', () => ({
  manifestPath: vi.fn((root: string) => `${root}/.ppg/manifest.json`),
}));

vi.mock('../../lib/name.js', () => ({
  normalizeName: vi.fn((name: string) => name),
}));

vi.mock('../../lib/vars.js', () => ({
  parseVars: vi.fn(() => ({})),
}));

// --- Imports (after mocks) ---

import fs from 'node:fs/promises';
import { loadConfig, resolveAgentConfig } from '../config.js';
import { readManifest, updateManifest, resolveWorktree } from '../manifest.js';
import { getRepoRoot, getCurrentBranch, createWorktree, adoptWorktree } from '../worktree.js';
import { setupWorktreeEnv } from '../env.js';
import { loadTemplate } from '../template.js';
import { spawnAgent } from '../agent.js';
import * as tmux from '../tmux.js';
import { openTerminalWindow } from '../terminal.js';
import { worktreeId as genWorktreeId, agentId as genAgentId, sessionId as genSessionId } from '../../lib/id.js';
import { performSpawn } from './spawn.js';

const mockedFs = vi.mocked(fs);
const mockedLoadConfig = vi.mocked(loadConfig);
const mockedResolveAgentConfig = vi.mocked(resolveAgentConfig);
const mockedReadManifest = vi.mocked(readManifest);
const mockedUpdateManifest = vi.mocked(updateManifest);
const mockedResolveWorktree = vi.mocked(resolveWorktree);
const mockedCreateWorktree = vi.mocked(createWorktree);
const mockedSpawnAgent = vi.mocked(spawnAgent);
const mockedEnsureSession = vi.mocked(tmux.ensureSession);
const mockedCreateWindow = vi.mocked(tmux.createWindow);
const mockedSplitPane = vi.mocked(tmux.splitPane);
const mockedLoadTemplate = vi.mocked(loadTemplate);

const PROJECT_ROOT = '/tmp/project';
const SESSION_NAME = 'ppg-test';

const DEFAULT_CONFIG: Config = {
  sessionName: SESSION_NAME,
  defaultAgent: 'claude',
  agents: {
    claude: { name: 'claude', command: 'claude', interactive: true },
  },
  envFiles: ['.env'],
  symlinkNodeModules: true,
};

const AGENT_CONFIG = { name: 'claude', command: 'claude', interactive: true };

const DEFAULT_MANIFEST: Manifest = {
  version: 1,
  projectRoot: PROJECT_ROOT,
  sessionName: SESSION_NAME,
  agents: {},
  worktrees: {},
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
};

function makeManifestState(): Manifest {
  return structuredClone(DEFAULT_MANIFEST);
}

function setupDefaultMocks() {
  vi.mocked(getRepoRoot).mockResolvedValue(PROJECT_ROOT);
  mockedLoadConfig.mockResolvedValue(DEFAULT_CONFIG);
  mockedResolveAgentConfig.mockReturnValue(AGENT_CONFIG);
  mockedFs.access.mockResolvedValue(undefined);
  mockedReadManifest.mockResolvedValue(makeManifestState());
  mockedUpdateManifest.mockImplementation(async (_root, updater) => {
    return updater(makeManifestState());
  });
  vi.mocked(getCurrentBranch).mockResolvedValue('main');
  vi.mocked(genWorktreeId).mockReturnValue('wt-abc123');
  vi.mocked(genAgentId).mockReturnValue('ag-test0001');
  vi.mocked(genSessionId).mockReturnValue('session-uuid-1');
  mockedCreateWorktree.mockResolvedValue(`${PROJECT_ROOT}/.worktrees/wt-abc123`);
  vi.mocked(adoptWorktree).mockResolvedValue(`${PROJECT_ROOT}/.worktrees/wt-abc123`);
  mockedEnsureSession.mockResolvedValue(undefined);
  mockedCreateWindow.mockResolvedValue(`${SESSION_NAME}:1`);
  vi.mocked(setupWorktreeEnv).mockResolvedValue(undefined);
  mockedSpawnAgent.mockResolvedValue({
    id: 'ag-test0001',
    name: 'claude',
    agentType: 'claude',
    status: 'running',
    tmuxTarget: `${SESSION_NAME}:1`,
    prompt: 'Do the task',
    startedAt: '2026-01-01T00:00:00.000Z',
    sessionId: 'session-uuid-1',
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  setupDefaultMocks();
});

describe('performSpawn', () => {
  describe('new worktree (default path)', () => {
    test('given prompt option, should create worktree, setup env, create tmux, spawn agent, return result', async () => {
      const result = await performSpawn({ prompt: 'Do the task', name: 'feature-x' });

      expect(mockedCreateWorktree).toHaveBeenCalledWith(PROJECT_ROOT, 'wt-abc123', {
        branch: 'ppg/feature-x',
        base: 'main',
      });
      expect(vi.mocked(setupWorktreeEnv)).toHaveBeenCalledWith(
        PROJECT_ROOT,
        `${PROJECT_ROOT}/.worktrees/wt-abc123`,
        DEFAULT_CONFIG,
      );
      expect(mockedEnsureSession).toHaveBeenCalledWith(SESSION_NAME);
      expect(mockedCreateWindow).toHaveBeenCalledWith(
        SESSION_NAME,
        'feature-x',
        `${PROJECT_ROOT}/.worktrees/wt-abc123`,
      );
      expect(mockedSpawnAgent).toHaveBeenCalledWith(expect.objectContaining({
        agentId: 'ag-test0001',
        agentConfig: AGENT_CONFIG,
        projectRoot: PROJECT_ROOT,
      }));

      expect(result).toEqual({
        worktree: {
          id: 'wt-abc123',
          name: 'feature-x',
          branch: 'ppg/feature-x',
          path: `${PROJECT_ROOT}/.worktrees/wt-abc123`,
          tmuxWindow: `${SESSION_NAME}:1`,
        },
        agents: [{
          id: 'ag-test0001',
          tmuxTarget: `${SESSION_NAME}:1`,
          sessionId: 'session-uuid-1',
        }],
      });
    });

    test('given no name, should use worktree ID as name', async () => {
      await performSpawn({ prompt: 'Do the task' });

      expect(mockedCreateWorktree).toHaveBeenCalledWith(PROJECT_ROOT, 'wt-abc123', {
        branch: 'ppg/wt-abc123',
        base: 'main',
      });
    });

    test('given --base option, should use it instead of current branch', async () => {
      await performSpawn({ prompt: 'Do the task', base: 'develop' });

      expect(mockedCreateWorktree).toHaveBeenCalledWith(PROJECT_ROOT, 'wt-abc123', {
        branch: 'ppg/wt-abc123',
        base: 'develop',
      });
      expect(vi.mocked(getCurrentBranch)).not.toHaveBeenCalled();
    });

    test('given --open, should call openTerminalWindow', async () => {
      vi.mocked(openTerminalWindow).mockResolvedValue(undefined);

      await performSpawn({ prompt: 'Do the task', open: true });

      expect(vi.mocked(openTerminalWindow)).toHaveBeenCalledWith(
        SESSION_NAME,
        `${SESSION_NAME}:1`,
        'wt-abc123',
      );
    });

    test('given count=2 with --split, should split pane for second agent', async () => {
      let agentCallCount = 0;
      vi.mocked(genAgentId).mockImplementation(() => {
        agentCallCount++;
        return `ag-test000${agentCallCount}`;
      });
      mockedSplitPane.mockResolvedValue({ paneId: '%2', target: `${SESSION_NAME}:1.1` });
      mockedSpawnAgent
        .mockResolvedValueOnce({
          id: 'ag-test0001', name: 'claude', agentType: 'claude', status: 'running',
          tmuxTarget: `${SESSION_NAME}:1`, prompt: 'Do the task', startedAt: '2026-01-01T00:00:00.000Z',
          sessionId: 'session-uuid-1',
        })
        .mockResolvedValueOnce({
          id: 'ag-test0002', name: 'claude', agentType: 'claude', status: 'running',
          tmuxTarget: `${SESSION_NAME}:1.1`, prompt: 'Do the task', startedAt: '2026-01-01T00:00:00.000Z',
          sessionId: 'session-uuid-1',
        });

      const result = await performSpawn({ prompt: 'Do the task', count: 2, split: true });

      expect(mockedSplitPane).toHaveBeenCalledWith(`${SESSION_NAME}:1`, 'horizontal', expect.any(String));
      expect(result.agents).toHaveLength(2);
    });

    test('given new worktree, should register skeleton in manifest before spawning agents', async () => {
      // Capture the updater functions to inspect what each one does in isolation
      const updaters: Array<(m: Manifest) => Manifest | Promise<Manifest>> = [];
      mockedUpdateManifest.mockImplementation(async (_root, updater) => {
        updaters.push(updater);
        const m = makeManifestState();
        return updater(m);
      });

      await performSpawn({ prompt: 'Do the task', name: 'feature-x' });

      // First updater should register the skeleton worktree (no agents yet)
      const skeletonResult = await updaters[0](makeManifestState());
      expect(skeletonResult.worktrees['wt-abc123']).toBeDefined();
      expect(Object.keys(skeletonResult.worktrees['wt-abc123'].agents)).toHaveLength(0);

      // Second updater should add agent to an existing worktree entry
      const withWorktree = makeManifestState();
      withWorktree.worktrees['wt-abc123'] = structuredClone(skeletonResult.worktrees['wt-abc123']);
      const agentResult = await updaters[1](withWorktree);
      expect(agentResult.worktrees['wt-abc123'].agents['ag-test0001']).toBeDefined();
    });
  });

  describe('existing branch (--branch)', () => {
    test('given --branch, should adopt worktree from existing branch', async () => {
      const result = await performSpawn({ prompt: 'Do the task', branch: 'ppg/fix-bug' });

      expect(vi.mocked(adoptWorktree)).toHaveBeenCalledWith(PROJECT_ROOT, 'wt-abc123', 'ppg/fix-bug');
      expect(mockedCreateWorktree).not.toHaveBeenCalled();
      expect(result.worktree.branch).toBe('ppg/fix-bug');
    });
  });

  describe('existing worktree (--worktree)', () => {
    test('given --worktree, should add agent to existing worktree', async () => {
      const existingWt: WorktreeEntry = {
        id: 'wt-exist1',
        name: 'existing',
        path: `${PROJECT_ROOT}/.worktrees/wt-exist1`,
        branch: 'ppg/existing',
        baseBranch: 'main',
        status: 'active',
        tmuxWindow: `${SESSION_NAME}:2`,
        agents: {},
        createdAt: '2026-01-01T00:00:00.000Z',
      };
      mockedResolveWorktree.mockReturnValue(existingWt);

      mockedCreateWindow.mockResolvedValue(`${SESSION_NAME}:3`);
      mockedSpawnAgent.mockResolvedValue({
        id: 'ag-test0001', name: 'claude', agentType: 'claude', status: 'running',
        tmuxTarget: `${SESSION_NAME}:3`, prompt: 'Do the task', startedAt: '2026-01-01T00:00:00.000Z',
        sessionId: 'session-uuid-1',
      });

      const result = await performSpawn({ prompt: 'Do the task', worktree: 'wt-exist1' });

      expect(mockedCreateWorktree).not.toHaveBeenCalled();
      expect(vi.mocked(adoptWorktree)).not.toHaveBeenCalled();
      expect(result.worktree.id).toBe('wt-exist1');
      expect(result.agents).toHaveLength(1);
    });

    test('given --worktree with no tmux window, should lazily create one and persist before spawning', async () => {
      const existingWt: WorktreeEntry = {
        id: 'wt-exist1',
        name: 'existing',
        path: `${PROJECT_ROOT}/.worktrees/wt-exist1`,
        branch: 'ppg/existing',
        baseBranch: 'main',
        status: 'active',
        tmuxWindow: '',
        agents: {},
        createdAt: '2026-01-01T00:00:00.000Z',
      };
      mockedResolveWorktree.mockReturnValue(existingWt);
      mockedCreateWindow.mockResolvedValue(`${SESSION_NAME}:5`);

      // Capture updater functions to verify ordering
      const updaters: Array<(m: Manifest) => Manifest | Promise<Manifest>> = [];
      mockedUpdateManifest.mockImplementation(async (_root, updater) => {
        updaters.push(updater);
        const m = makeManifestState();
        m.worktrees['wt-exist1'] = structuredClone(existingWt);
        return updater(m);
      });

      mockedSpawnAgent.mockResolvedValue({
        id: 'ag-test0001', name: 'claude', agentType: 'claude', status: 'running',
        tmuxTarget: `${SESSION_NAME}:5`, prompt: 'Do the task', startedAt: '2026-01-01T00:00:00.000Z',
        sessionId: 'session-uuid-1',
      });

      const result = await performSpawn({ prompt: 'Do the task', worktree: 'wt-exist1' });

      expect(mockedEnsureSession).toHaveBeenCalledWith(SESSION_NAME);
      expect(mockedCreateWindow).toHaveBeenCalledWith(SESSION_NAME, 'existing', existingWt.path);
      expect(result.worktree.tmuxWindow).toBe(`${SESSION_NAME}:5`);

      // First updater should persist the tmux window (before agent spawn)
      const windowInput = makeManifestState();
      windowInput.worktrees['wt-exist1'] = structuredClone(existingWt);
      const windowResult = await updaters[0](windowInput);
      expect(windowResult.worktrees['wt-exist1'].tmuxWindow).toBe(`${SESSION_NAME}:5`);
      expect(Object.keys(windowResult.worktrees['wt-exist1'].agents)).toHaveLength(0);
    });

    test('given spawn failure on existing worktree with lazy window, should persist tmux window but no agents', async () => {
      const existingWt: WorktreeEntry = {
        id: 'wt-exist1',
        name: 'existing',
        path: `${PROJECT_ROOT}/.worktrees/wt-exist1`,
        branch: 'ppg/existing',
        baseBranch: 'main',
        status: 'active',
        tmuxWindow: '',
        agents: {},
        createdAt: '2026-01-01T00:00:00.000Z',
      };
      mockedResolveWorktree.mockReturnValue(existingWt);
      mockedCreateWindow.mockResolvedValue(`${SESSION_NAME}:7`);

      let persistedTmuxWindow = '';
      mockedUpdateManifest.mockImplementation(async (_root, updater) => {
        const m = makeManifestState();
        m.worktrees['wt-exist1'] = structuredClone(existingWt);
        const result = await updater(m);
        persistedTmuxWindow = result.worktrees['wt-exist1']?.tmuxWindow ?? '';
        return result;
      });

      mockedSpawnAgent.mockRejectedValueOnce(new Error('spawn failed'));

      await expect(performSpawn({ prompt: 'Do work', worktree: 'wt-exist1' }))
        .rejects.toThrow('spawn failed');

      // tmux window should have been persisted before the spawn failure
      expect(persistedTmuxWindow).toBe(`${SESSION_NAME}:7`);
      expect(mockedUpdateManifest).toHaveBeenCalledTimes(1);
    });

    test('given unknown worktree ref, should throw WorktreeNotFoundError', async () => {
      mockedResolveWorktree.mockReturnValue(undefined);

      await expect(performSpawn({ prompt: 'Do the task', worktree: 'nonexistent' }))
        .rejects.toThrow('Worktree not found: nonexistent');
    });
  });

  describe('prompt resolution', () => {
    test('given --branch and --worktree, should throw INVALID_ARGS', async () => {
      await expect(performSpawn({ prompt: 'Do the task', branch: 'foo', worktree: 'bar' }))
        .rejects.toThrow('--branch and --worktree are mutually exclusive');
    });

    test('given --branch and --base, should throw INVALID_ARGS', async () => {
      await expect(performSpawn({ prompt: 'Do the task', branch: 'foo', base: 'bar' }))
        .rejects.toThrow('--branch and --base are mutually exclusive');
    });

    test('given no prompt/promptFile/template, should throw INVALID_ARGS', async () => {
      await expect(performSpawn({}))
        .rejects.toThrow('One of --prompt, --prompt-file, or --template is required');
    });

    test('given --prompt-file, should read prompt from file', async () => {
      mockedFs.readFile.mockResolvedValue('File prompt content');

      await performSpawn({ promptFile: '/tmp/prompt.md' });

      expect(mockedFs.readFile).toHaveBeenCalledWith('/tmp/prompt.md', 'utf-8');
    });

    test('given --template, should load template by name', async () => {
      mockedLoadTemplate.mockResolvedValue('Template content with {{BRANCH}}');

      await performSpawn({ template: 'my-template' });

      expect(mockedLoadTemplate).toHaveBeenCalledWith(PROJECT_ROOT, 'my-template');
    });
  });
});
