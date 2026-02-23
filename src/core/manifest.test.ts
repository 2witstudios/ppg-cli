import { describe, test, expect } from 'vitest';
import { resolveWorktree } from './manifest.js';
import type { Manifest, WorktreeEntry } from '../types/manifest.js';

function createWorktree(overrides: Partial<WorktreeEntry> = {}): WorktreeEntry {
  return {
    id: 'wt-abc123',
    name: 'feature-auth',
    path: '/tmp/.worktrees/wt-abc123',
    branch: 'ppg/feature-auth',
    baseBranch: 'main',
    status: 'active',
    tmuxWindow: 'ppg:1',
    agents: {},
    createdAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  };
}

function createManifest(worktrees: Record<string, WorktreeEntry> = {}): Manifest {
  return {
    version: 1,
    projectRoot: '/tmp/project',
    sessionName: 'ppg',
    worktrees,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
  };
}

describe('resolveWorktree', () => {
  test('given a worktree ID, should return the worktree', () => {
    const wt = createWorktree({ id: 'wt-abc123' });
    const manifest = createManifest({ 'wt-abc123': wt });

    const actual = resolveWorktree(manifest, 'wt-abc123');
    const expected = wt;

    expect(actual).toBe(expected);
  });

  test('given a worktree name, should return the worktree', () => {
    const wt = createWorktree({ id: 'wt-abc123', name: 'feature-auth' });
    const manifest = createManifest({ 'wt-abc123': wt });

    const actual = resolveWorktree(manifest, 'feature-auth');
    const expected = wt;

    expect(actual).toBe(expected);
  });

  test('given a branch name, should return the worktree', () => {
    const wt = createWorktree({ id: 'wt-abc123', branch: 'ppg/feature-auth' });
    const manifest = createManifest({ 'wt-abc123': wt });

    const actual = resolveWorktree(manifest, 'ppg/feature-auth');
    const expected = wt;

    expect(actual).toBe(expected);
  });

  test('given a nonexistent ref, should return undefined', () => {
    const manifest = createManifest({});

    const actual = resolveWorktree(manifest, 'wt-nope');
    const expected = undefined;

    expect(actual).toBe(expected);
  });

  test('given an ID that matches, should prefer ID over name match', () => {
    const wtById = createWorktree({ id: 'wt-abc123', name: 'other-name' });
    const wtByName = createWorktree({ id: 'wt-def456', name: 'wt-abc123' });
    const manifest = createManifest({
      'wt-abc123': wtById,
      'wt-def456': wtByName,
    });

    const actual = resolveWorktree(manifest, 'wt-abc123');
    const expected = wtById;

    expect(actual).toBe(expected);
  });
});
