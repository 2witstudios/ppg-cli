import { describe, test, expect, vi, beforeEach } from 'vitest';
import type { Manifest, AgentEntry, WorktreeEntry } from '../../types/manifest.js';
import type { PaneInfo } from '../process-manager.js';

// --- Mocks ---

vi.mock('../manifest.js', () => ({
  readManifest: vi.fn(),
  updateManifest: vi.fn(),
  findAgent: vi.fn(),
  resolveWorktree: vi.fn(),
}));

vi.mock('../agent.js', () => ({
  killAgent: vi.fn(async () => {}),
  killAgents: vi.fn(async () => {}),
}));

vi.mock('../pr.js', () => ({
  checkPrState: vi.fn(async () => 'UNKNOWN'),
}));

vi.mock('../cleanup.js', () => ({
  cleanupWorktree: vi.fn(async () => ({
    worktreeId: 'wt-abc123',
    manifestUpdated: true,
    tmuxKilled: 1,
    tmuxSkipped: 0,
    tmuxFailed: 0,
    selfProtected: false,
    selfProtectedTargets: [],
  })),
}));

vi.mock('../self.js', () => ({
  excludeSelf: vi.fn(),
}));

const mockKillPane = vi.fn(async () => {});
vi.mock('../backend.js', () => ({
  getBackend: () => ({
    killPane: mockKillPane,
  }),
}));

import { performKill } from './kill.js';
import { readManifest, updateManifest, findAgent, resolveWorktree } from '../manifest.js';
import { killAgent, killAgents } from '../agent.js';
import { checkPrState } from '../pr.js';
import { cleanupWorktree } from '../cleanup.js';
import { excludeSelf } from '../self.js';
import { PpgError } from '../../lib/errors.js';

const killPane = mockKillPane;

// --- Helpers ---

function makeAgent(id: string, overrides: Partial<AgentEntry> = {}): AgentEntry {
  return {
    id,
    name: 'test',
    agentType: 'claude',
    status: 'running',
    tmuxTarget: 'ppg:1.0',
    prompt: 'do stuff',
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
    agents: {},
    createdAt: new Date().toISOString(),
    ...overrides,
  };
}

function makeManifest(worktrees: Record<string, WorktreeEntry> = {}): Manifest {
  return {
    version: 1,
    projectRoot: '/project',
    sessionName: 'ppg',
    worktrees,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
}

// Shared manifest reference for updateManifest mock
let _manifest: Manifest;
function currentManifest(): Manifest {
  return JSON.parse(JSON.stringify(_manifest));
}

// --- Tests ---

describe('performKill', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    _manifest = makeManifest();
    // Establish defaults for all mocks after clearing
    vi.mocked(readManifest).mockResolvedValue(_manifest);
    vi.mocked(updateManifest).mockImplementation(async (_root: string, updater: (m: any) => any) => {
      return updater(currentManifest());
    });
    vi.mocked(findAgent).mockReturnValue(undefined);
    vi.mocked(resolveWorktree).mockReturnValue(undefined);
    vi.mocked(checkPrState).mockResolvedValue('UNKNOWN');
    vi.mocked(excludeSelf).mockImplementation((agents: AgentEntry[]) => ({ safe: agents, skipped: [] }));
  });

  test('throws INVALID_ARGS when no target specified', async () => {
    const err = await performKill({ projectRoot: '/project' }).catch((e) => e);
    expect(err).toBeInstanceOf(PpgError);
    expect((err as PpgError).code).toBe('INVALID_ARGS');
  });

  describe('single agent kill', () => {
    beforeEach(() => {
      const agent = makeAgent('ag-12345678');
      const wt = makeWorktree({ agents: { 'ag-12345678': agent } });
      _manifest = makeManifest({ 'wt-abc123': wt });
      vi.mocked(readManifest).mockResolvedValue(_manifest);
      vi.mocked(findAgent).mockReturnValue({ worktree: wt, agent });
    });

    test('kills a running agent and updates manifest', async () => {
      const result = await performKill({
        projectRoot: '/project',
        agent: 'ag-12345678',
      });

      expect(killAgent).toHaveBeenCalled();
      expect(updateManifest).toHaveBeenCalled();
      expect(result.success).toBe(true);
      expect(result.killed).toEqual(['ag-12345678']);
    });

    test('manifest updater sets agent status to gone', async () => {
      await performKill({
        projectRoot: '/project',
        agent: 'ag-12345678',
      });

      // Verify the updater was called and inspect what it does
      const updaterCall = vi.mocked(updateManifest).mock.calls[0];
      expect(updaterCall[0]).toBe('/project');
      const updater = updaterCall[1];

      // Run the updater against a test manifest to verify the mutation
      const testManifest = makeManifest({
        'wt-abc123': makeWorktree({
          agents: { 'ag-12345678': makeAgent('ag-12345678') },
        }),
      });
      // findAgent mock returns matching agent from test manifest
      vi.mocked(findAgent).mockReturnValue({
        worktree: testManifest.worktrees['wt-abc123'],
        agent: testManifest.worktrees['wt-abc123'].agents['ag-12345678'],
      });
      const result = updater(testManifest) as Manifest;
      expect(result.worktrees['wt-abc123'].agents['ag-12345678'].status).toBe('gone');
    });

    test('skips kill for terminal-state agent', async () => {
      const goneAgent = makeAgent('ag-12345678', { status: 'gone' });
      const wt = makeWorktree({ agents: { 'ag-12345678': goneAgent } });
      vi.mocked(findAgent).mockReturnValue({ worktree: wt, agent: goneAgent });

      const result = await performKill({
        projectRoot: '/project',
        agent: 'ag-12345678',
      });

      expect(killAgent).not.toHaveBeenCalled();
      expect(result.success).toBe(true);
      expect(result.killed).toEqual([]);
      expect(result.message).toContain('already gone');
    });

    test('throws AgentNotFoundError for unknown agent', async () => {
      vi.mocked(findAgent).mockReturnValue(undefined);

      const err = await performKill({ projectRoot: '/project', agent: 'ag-unknown' }).catch((e) => e);
      expect(err).toBeInstanceOf(PpgError);
      expect((err as PpgError).code).toBe('AGENT_NOT_FOUND');
    });

    test('self-protection returns success:false with skipped', async () => {
      const agent = makeAgent('ag-12345678');
      vi.mocked(excludeSelf).mockReturnValue({
        safe: [],
        skipped: [agent],
      });

      const result = await performKill({
        projectRoot: '/project',
        agent: 'ag-12345678',
        selfPaneId: '%5',
        paneMap: new Map(),
      });

      expect(killAgent).not.toHaveBeenCalled();
      expect(result.success).toBe(false);
      expect(result.killed).toEqual([]);
      expect(result.skipped).toEqual(['ag-12345678']);
    });

    test('--delete removes agent from manifest', async () => {
      const result = await performKill({
        projectRoot: '/project',
        agent: 'ag-12345678',
        delete: true,
      });

      expect(killAgent).toHaveBeenCalled();
      expect(killPane).toHaveBeenCalled();
      expect(updateManifest).toHaveBeenCalled();
      expect(result.success).toBe(true);
      expect(result.deleted).toEqual(['ag-12345678']);
    });

    test('--delete manifest updater removes agent entry', async () => {
      await performKill({
        projectRoot: '/project',
        agent: 'ag-12345678',
        delete: true,
      });

      const updaterCall = vi.mocked(updateManifest).mock.calls[0];
      const updater = updaterCall[1];

      const testManifest = makeManifest({
        'wt-abc123': makeWorktree({
          agents: { 'ag-12345678': makeAgent('ag-12345678') },
        }),
      });
      vi.mocked(findAgent).mockReturnValue({
        worktree: testManifest.worktrees['wt-abc123'],
        agent: testManifest.worktrees['wt-abc123'].agents['ag-12345678'],
      });
      const result = updater(testManifest) as Manifest;
      expect(result.worktrees['wt-abc123'].agents['ag-12345678']).toBeUndefined();
    });

    test('--delete on terminal agent skips kill but still deletes', async () => {
      const idleAgent = makeAgent('ag-12345678', { status: 'idle' });
      const wt = makeWorktree({ agents: { 'ag-12345678': idleAgent } });
      vi.mocked(findAgent).mockReturnValue({ worktree: wt, agent: idleAgent });

      const result = await performKill({
        projectRoot: '/project',
        agent: 'ag-12345678',
        delete: true,
      });

      expect(killAgent).not.toHaveBeenCalled();
      expect(killPane).toHaveBeenCalled();
      expect(result.success).toBe(true);
      expect(result.deleted).toEqual(['ag-12345678']);
      expect(result.killed).toEqual([]);
    });

    test('propagates killAgent errors', async () => {
      vi.mocked(killAgent).mockRejectedValue(new Error('tmux crash'));

      const err = await performKill({
        projectRoot: '/project',
        agent: 'ag-12345678',
      }).catch((e) => e);

      expect(err).toBeInstanceOf(Error);
      expect(err.message).toBe('tmux crash');
    });
  });

  describe('worktree kill', () => {
    let agent1: AgentEntry;
    let agent2: AgentEntry;
    let wt: WorktreeEntry;

    beforeEach(() => {
      agent1 = makeAgent('ag-aaaaaaaa', { tmuxTarget: 'ppg:1.0' });
      agent2 = makeAgent('ag-bbbbbbbb', { tmuxTarget: 'ppg:1.1' });
      wt = makeWorktree({
        agents: {
          'ag-aaaaaaaa': agent1,
          'ag-bbbbbbbb': agent2,
        },
      });
      _manifest = makeManifest({ 'wt-abc123': wt });
      vi.mocked(readManifest).mockResolvedValue(_manifest);
      vi.mocked(resolveWorktree).mockReturnValue(wt);
    });

    test('kills all running agents in worktree', async () => {
      const result = await performKill({
        projectRoot: '/project',
        worktree: 'wt-abc123',
      });

      expect(killAgents).toHaveBeenCalledWith([agent1, agent2]);
      expect(result.success).toBe(true);
      expect(result.killed).toEqual(['ag-aaaaaaaa', 'ag-bbbbbbbb']);
    });

    test('throws WorktreeNotFoundError for unknown worktree', async () => {
      vi.mocked(resolveWorktree).mockReturnValue(undefined);

      const err = await performKill({ projectRoot: '/project', worktree: 'wt-unknown' }).catch((e) => e);
      expect(err).toBeInstanceOf(PpgError);
      expect((err as PpgError).code).toBe('WORKTREE_NOT_FOUND');
    });

    test('--remove triggers worktree cleanup', async () => {
      await performKill({
        projectRoot: '/project',
        worktree: 'wt-abc123',
        remove: true,
      });

      expect(cleanupWorktree).toHaveBeenCalled();
    });

    test('--delete removes worktree from manifest', async () => {
      const result = await performKill({
        projectRoot: '/project',
        worktree: 'wt-abc123',
        delete: true,
      });

      expect(cleanupWorktree).toHaveBeenCalled();
      expect(result.deleted).toEqual(['wt-abc123']);
    });

    test('--delete skips worktree with open PR', async () => {
      vi.mocked(checkPrState).mockResolvedValue('OPEN');

      const result = await performKill({
        projectRoot: '/project',
        worktree: 'wt-abc123',
        delete: true,
      });

      expect(cleanupWorktree).not.toHaveBeenCalled();
      expect(result.deleted).toEqual([]);
      expect(result.skippedOpenPrs).toEqual(['wt-abc123']);
    });

    test('--delete --include-open-prs overrides PR check', async () => {
      vi.mocked(checkPrState).mockResolvedValue('OPEN');

      const result = await performKill({
        projectRoot: '/project',
        worktree: 'wt-abc123',
        delete: true,
        includeOpenPrs: true,
      });

      expect(cleanupWorktree).toHaveBeenCalled();
      expect(result.deleted).toEqual(['wt-abc123']);
    });

    test('filters non-running agents', async () => {
      const idleAgent = makeAgent('ag-cccccccc', { status: 'idle' });
      const wtMixed = makeWorktree({
        agents: {
          'ag-aaaaaaaa': agent1,
          'ag-cccccccc': idleAgent,
        },
      });
      vi.mocked(resolveWorktree).mockReturnValue(wtMixed);

      const result = await performKill({
        projectRoot: '/project',
        worktree: 'wt-abc123',
      });

      expect(result.killed).toEqual(['ag-aaaaaaaa']);
    });
  });

  describe('kill all', () => {
    let agent1: AgentEntry;
    let agent2: AgentEntry;
    let wt1: WorktreeEntry;
    let wt2: WorktreeEntry;

    beforeEach(() => {
      agent1 = makeAgent('ag-aaaaaaaa');
      agent2 = makeAgent('ag-bbbbbbbb');
      wt1 = makeWorktree({
        id: 'wt-111111',
        agents: { 'ag-aaaaaaaa': agent1 },
      });
      wt2 = makeWorktree({
        id: 'wt-222222',
        name: 'other-wt',
        agents: { 'ag-bbbbbbbb': agent2 },
      });
      _manifest = makeManifest({ 'wt-111111': wt1, 'wt-222222': wt2 });
      vi.mocked(readManifest).mockResolvedValue(_manifest);
      // resolveWorktree is called inside removeWorktreeCleanup for --delete/--remove
      vi.mocked(resolveWorktree).mockImplementation((_m, ref) => {
        if (ref === 'wt-111111') return wt1;
        if (ref === 'wt-222222') return wt2;
        return undefined;
      });
    });

    test('kills agents across all worktrees', async () => {
      const result = await performKill({
        projectRoot: '/project',
        all: true,
      });

      expect(killAgents).toHaveBeenCalled();
      expect(result.success).toBe(true);
      expect(result.killed).toHaveLength(2);
      expect(result.killed).toContain('ag-aaaaaaaa');
      expect(result.killed).toContain('ag-bbbbbbbb');
    });

    test('includes worktreeCount in result', async () => {
      const result = await performKill({
        projectRoot: '/project',
        all: true,
      });

      expect(result.worktreeCount).toBe(2);
    });

    test('--delete removes all active worktrees', async () => {
      const result = await performKill({
        projectRoot: '/project',
        all: true,
        delete: true,
      });

      expect(cleanupWorktree).toHaveBeenCalledTimes(2);
      expect(result.deleted).toHaveLength(2);
    });

    test('--remove triggers cleanup without manifest deletion', async () => {
      const result = await performKill({
        projectRoot: '/project',
        all: true,
        remove: true,
      });

      expect(cleanupWorktree).toHaveBeenCalledTimes(2);
      expect(result.removed).toHaveLength(2);
      // --remove without --delete: cleanup happens but entries stay in manifest
      expect(result.deleted).toEqual([]);
    });

    test('self-protection filters agents', async () => {
      vi.mocked(excludeSelf).mockReturnValue({
        safe: [agent2],
        skipped: [agent1],
      });

      const result = await performKill({
        projectRoot: '/project',
        all: true,
        selfPaneId: '%5',
        paneMap: new Map(),
      });

      expect(result.killed).toEqual(['ag-bbbbbbbb']);
      expect(result.skipped).toEqual(['ag-aaaaaaaa']);
    });
  });
});
