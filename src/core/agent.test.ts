import { describe, test, expect, vi, beforeEach } from 'vitest';
import { makeAgent, makePaneInfo } from '../test-fixtures.js';
import type { PaneInfo } from './tmux.js';

// Mock node:fs/promises
vi.mock('node:fs/promises', () => ({
  default: {
    access: vi.fn(),
    mkdir: vi.fn(),
    writeFile: vi.fn(),
  },
}));

// Mock tmux module
vi.mock('./tmux.js', () => ({
  getPaneInfo: vi.fn(),
  listSessionPanes: vi.fn(),
  sendKeys: vi.fn(),
  sendCtrlC: vi.fn(),
  killPane: vi.fn(),
  ensureSession: vi.fn(),
  createWindow: vi.fn(),
}));

// Mock manifest module
vi.mock('./manifest.js', () => ({
  updateManifest: vi.fn(),
}));

// Mock template module
vi.mock('./template.js', () => ({
  renderTemplate: vi.fn((content: string) => content),
}));

import fs from 'node:fs/promises';
import { getPaneInfo } from './tmux.js';
import { checkAgentStatus } from './agent.js';

const mockedAccess = vi.mocked(fs.access);
const mockedGetPaneInfo = vi.mocked(getPaneInfo);

const PROJECT_ROOT = '/tmp/project';

beforeEach(() => {
  vi.clearAllMocks();
});

describe('checkAgentStatus', () => {
  test('given already completed status, should return same status', async () => {
    const agent = makeAgent({ status: 'completed', exitCode: 0 });
    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'completed', exitCode: 0 });
  });

  test('given already failed status, should return same status', async () => {
    const agent = makeAgent({ status: 'failed', exitCode: 1 });
    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'failed', exitCode: 1 });
  });

  test('given already killed status, should return same status', async () => {
    const agent = makeAgent({ status: 'killed' });
    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'killed', exitCode: undefined });
  });

  test('given already lost status, should return same status', async () => {
    const agent = makeAgent({ status: 'lost' });
    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'lost', exitCode: undefined });
  });

  test('given result file exists, should return completed', async () => {
    const agent = makeAgent({ status: 'running' });
    // fs.access succeeds → file exists
    mockedAccess.mockResolvedValue(undefined);

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'completed' });
  });

  test('given no result file and pane not found, should return lost', async () => {
    const agent = makeAgent({ status: 'running' });
    // fs.access fails → no result file
    mockedAccess.mockRejectedValue(new Error('ENOENT'));
    // getPaneInfo returns null → pane doesn't exist
    mockedGetPaneInfo.mockResolvedValue(null);

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'lost' });
  });

  test('given dead pane with exit 0, should return completed', async () => {
    const agent = makeAgent({ status: 'running' });
    mockedAccess.mockRejectedValue(new Error('ENOENT'));
    mockedGetPaneInfo.mockResolvedValue(
      makePaneInfo({ isDead: true, deadStatus: 0 }),
    );

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'completed', exitCode: 0 });
  });

  test('given dead pane with non-zero exit, should return failed', async () => {
    const agent = makeAgent({ status: 'running' });
    // All fs.access calls fail (no result file)
    mockedAccess.mockRejectedValue(new Error('ENOENT'));
    mockedGetPaneInfo.mockResolvedValue(
      makePaneInfo({ isDead: true, deadStatus: 1 }),
    );

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'failed', exitCode: 1 });
  });

  test('given dead pane with result file appearing, should return completed', async () => {
    const agent = makeAgent({ status: 'running' });
    // First access call fails (no result file at step 1), second succeeds (result file at step 3)
    mockedAccess
      .mockRejectedValueOnce(new Error('ENOENT'))
      .mockResolvedValueOnce(undefined);
    mockedGetPaneInfo.mockResolvedValue(
      makePaneInfo({ isDead: true, deadStatus: 1 }),
    );

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'completed', exitCode: 1 });
  });

  test('given current command is zsh (shell), should return failed', async () => {
    const agent = makeAgent({ status: 'running' });
    mockedAccess.mockRejectedValue(new Error('ENOENT'));
    mockedGetPaneInfo.mockResolvedValue(
      makePaneInfo({ currentCommand: 'zsh', isDead: false }),
    );

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'failed', exitCode: undefined });
  });

  test('given current command is bash (shell), should return failed', async () => {
    const agent = makeAgent({ status: 'running' });
    mockedAccess.mockRejectedValue(new Error('ENOENT'));
    mockedGetPaneInfo.mockResolvedValue(
      makePaneInfo({ currentCommand: 'bash', isDead: false }),
    );

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'failed', exitCode: undefined });
  });

  test('given current command is fish (shell), should return failed', async () => {
    const agent = makeAgent({ status: 'running' });
    mockedAccess.mockRejectedValue(new Error('ENOENT'));
    mockedGetPaneInfo.mockResolvedValue(
      makePaneInfo({ currentCommand: 'fish', isDead: false }),
    );

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'failed', exitCode: undefined });
  });

  test('given shell command but result file exists, should return completed', async () => {
    const agent = makeAgent({ status: 'running' });
    // First access fails (step 1), second succeeds (step 4 shell check)
    mockedAccess
      .mockRejectedValueOnce(new Error('ENOENT'))
      .mockResolvedValueOnce(undefined);
    mockedGetPaneInfo.mockResolvedValue(
      makePaneInfo({ currentCommand: 'zsh', isDead: false }),
    );

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'completed', exitCode: 0 });
  });

  test('given current command is claude (not shell), should return running', async () => {
    const agent = makeAgent({ status: 'running' });
    mockedAccess.mockRejectedValue(new Error('ENOENT'));
    mockedGetPaneInfo.mockResolvedValue(
      makePaneInfo({ currentCommand: 'claude', isDead: false }),
    );

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'running' });
  });

  test('given paneMap, should use it instead of getPaneInfo', async () => {
    const agent = makeAgent({ status: 'running' });
    mockedAccess.mockRejectedValue(new Error('ENOENT'));

    const paneMap = new Map<string, PaneInfo>();
    paneMap.set(agent.tmuxTarget, makePaneInfo({ currentCommand: 'claude' }));

    const result = await checkAgentStatus(agent, PROJECT_ROOT, paneMap);
    expect(result).toEqual({ status: 'running' });
    // Should not have called getPaneInfo since paneMap was provided
    expect(mockedGetPaneInfo).not.toHaveBeenCalled();
  });

  test('given paneMap without agent target, should return lost', async () => {
    const agent = makeAgent({ status: 'running' });
    mockedAccess.mockRejectedValue(new Error('ENOENT'));

    const paneMap = new Map<string, PaneInfo>();
    // Empty map — agent's target not found

    const result = await checkAgentStatus(agent, PROJECT_ROOT, paneMap);
    expect(result).toEqual({ status: 'lost' });
    expect(mockedGetPaneInfo).not.toHaveBeenCalled();
  });

  test('given spawning status, should check (not treated as terminal)', async () => {
    const agent = makeAgent({ status: 'spawning' });
    mockedAccess.mockRejectedValue(new Error('ENOENT'));
    mockedGetPaneInfo.mockResolvedValue(
      makePaneInfo({ currentCommand: 'claude', isDead: false }),
    );

    const result = await checkAgentStatus(agent, PROJECT_ROOT);
    expect(result).toEqual({ status: 'running' });
  });
});
