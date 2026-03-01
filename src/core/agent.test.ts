import { describe, test, expect, vi, beforeEach } from 'vitest';
import { makeAgent, makePaneInfo } from '../test-fixtures.js';
import type { PaneInfo } from './process-manager.js';

// Mock node:fs/promises
vi.mock('node:fs/promises', () => ({
  default: {
    access: vi.fn(),
    mkdir: vi.fn(),
    writeFile: vi.fn(),
  },
}));

// Mock backend module
const mockGetPaneInfo = vi.fn();
const mockListSessionPanes = vi.fn();
const mockSendKeys = vi.fn();
const mockSendCtrlC = vi.fn();
const mockKillPane = vi.fn();
const mockEnsureSession = vi.fn();
const mockCreateWindow = vi.fn();

vi.mock('./backend.js', () => ({
  getBackend: () => ({
    getPaneInfo: mockGetPaneInfo,
    listSessionPanes: mockListSessionPanes,
    sendKeys: mockSendKeys,
    sendCtrlC: mockSendCtrlC,
    killPane: mockKillPane,
    ensureSession: mockEnsureSession,
    createWindow: mockCreateWindow,
  }),
}));

// Mock manifest module
vi.mock('./manifest.js', () => ({
  updateManifest: vi.fn(),
}));

import { checkAgentStatus } from './agent.js';

const mockedGetPaneInfo = mockGetPaneInfo;

const PROJECT_ROOT = '/tmp/project';

beforeEach(() => {
  vi.clearAllMocks();
});

describe('checkAgentStatus', () => {
  test('given pane not found, should return gone', async () => {
    const agent = makeAgent({ status: 'running' });
    mockedGetPaneInfo.mockResolvedValue(null);

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'gone' });
  });

  test('given dead pane with exit 0, should return exited with exitCode', async () => {
    const agent = makeAgent({ status: 'running' });
    mockedGetPaneInfo.mockResolvedValue(
      makePaneInfo({ isDead: true, deadStatus: 0 }),
    );

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'exited', exitCode: 0 });
  });

  test('given dead pane with non-zero exit, should return exited with exitCode', async () => {
    const agent = makeAgent({ status: 'running' });
    mockedGetPaneInfo.mockResolvedValue(
      makePaneInfo({ isDead: true, deadStatus: 1 }),
    );

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'exited', exitCode: 1 });
  });

  test('given current command is zsh (shell), should return idle', async () => {
    const agent = makeAgent({ status: 'running' });
    mockedGetPaneInfo.mockResolvedValue(
      makePaneInfo({ currentCommand: 'zsh', isDead: false }),
    );

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'idle' });
  });

  test('given current command is bash (shell), should return idle', async () => {
    const agent = makeAgent({ status: 'running' });
    mockedGetPaneInfo.mockResolvedValue(
      makePaneInfo({ currentCommand: 'bash', isDead: false }),
    );

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'idle' });
  });

  test('given current command is fish (shell), should return idle', async () => {
    const agent = makeAgent({ status: 'running' });
    mockedGetPaneInfo.mockResolvedValue(
      makePaneInfo({ currentCommand: 'fish', isDead: false }),
    );

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'idle' });
  });

  test('given current command is claude (not shell), should return running', async () => {
    const agent = makeAgent({ status: 'running' });
    mockedGetPaneInfo.mockResolvedValue(
      makePaneInfo({ currentCommand: 'claude', isDead: false }),
    );

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'running' });
  });

  test('given paneMap, should use it instead of getPaneInfo', async () => {
    const agent = makeAgent({ status: 'running' });

    const paneMap = new Map<string, PaneInfo>();
    paneMap.set(agent.tmuxTarget, makePaneInfo({ currentCommand: 'claude' }));

    const result = await checkAgentStatus(agent, PROJECT_ROOT, paneMap);
    expect(result).toEqual({ status: 'running' });
    // Should not have called getPaneInfo since paneMap was provided
    expect(mockedGetPaneInfo).not.toHaveBeenCalled();
  });

  test('given paneMap without agent target, should return gone', async () => {
    const agent = makeAgent({ status: 'running' });

    const paneMap = new Map<string, PaneInfo>();
    // Empty map — agent's target not found

    const result = await checkAgentStatus(agent, PROJECT_ROOT, paneMap);
    expect(result).toEqual({ status: 'gone' });
    expect(mockedGetPaneInfo).not.toHaveBeenCalled();
  });

  test('always re-derives from tmux even if agent was previously idle', async () => {
    const agent = makeAgent({ status: 'idle' });
    mockedGetPaneInfo.mockResolvedValue(
      makePaneInfo({ currentCommand: 'claude', isDead: false }),
    );

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'running' });
  });

  test('always re-derives from tmux even if agent was previously gone', async () => {
    const agent = makeAgent({ status: 'gone' });
    mockedGetPaneInfo.mockResolvedValue(
      makePaneInfo({ currentCommand: 'claude', isDead: false }),
    );

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'running' });
  });
});
