import { describe, test, expect } from 'vitest';
import {
  GhNotFoundError,
  UnmergedWorkError,
  PgError,
} from './errors.js';

describe('GhNotFoundError', () => {
  test('given instantiation, should have correct code and message', () => {
    const err = new GhNotFoundError();

    expect(err).toBeInstanceOf(PgError);
    expect(err.code).toBe('GH_NOT_FOUND');
    expect(err.message).toContain('gh');
    expect(err.message).toContain('brew install gh');
    expect(err.name).toBe('GhNotFoundError');
  });
});

describe('UnmergedWorkError', () => {
  test('given single worktree name, should include it in message', () => {
    const err = new UnmergedWorkError(['fix-bug (ppg/fix-bug)']);

    expect(err).toBeInstanceOf(PgError);
    expect(err.code).toBe('UNMERGED_WORK');
    expect(err.message).toContain('1 worktree(s)');
    expect(err.message).toContain('fix-bug (ppg/fix-bug)');
    expect(err.message).toContain('--force');
    expect(err.message).toContain('ppg pr');
  });

  test('given multiple worktree names, should list all', () => {
    const err = new UnmergedWorkError([
      'fix-bug (ppg/fix-bug)',
      'add-feature (ppg/add-feature)',
    ]);

    expect(err.code).toBe('UNMERGED_WORK');
    expect(err.message).toContain('2 worktree(s)');
    expect(err.message).toContain('fix-bug');
    expect(err.message).toContain('add-feature');
  });
});
