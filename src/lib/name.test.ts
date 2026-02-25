import { describe, test, expect } from 'vitest';
import { normalizeName } from './name.js';

describe('normalizeName', () => {
  test('given spaces, should convert to hyphens', () => {
    expect(normalizeName('Fix Login Bug', 'fb')).toBe('fix-login-bug');
  });

  test('given underscores, should convert to hyphens', () => {
    expect(normalizeName('fix_login_bug', 'fb')).toBe('fix-login-bug');
  });

  test('given mixed spaces and underscores, should collapse to single hyphens', () => {
    expect(normalizeName('fix _ login  bug', 'fb')).toBe('fix-login-bug');
  });

  test('given uppercase, should lowercase', () => {
    expect(normalizeName('MyFeature', 'fb')).toBe('myfeature');
  });

  test('given git-invalid chars, should replace with hyphens', () => {
    expect(normalizeName('feat~1', 'fb')).toBe('feat-1');
    expect(normalizeName('fix^2', 'fb')).toBe('fix-2');
    expect(normalizeName('a:b', 'fb')).toBe('a-b');
    expect(normalizeName('test?', 'fb')).toBe('test');
    expect(normalizeName('glob*', 'fb')).toBe('glob');
    expect(normalizeName('ref[0]', 'fb')).toBe('ref-0');
    expect(normalizeName('a\\b', 'fb')).toBe('a-b');
    expect(normalizeName('a@b', 'fb')).toBe('a-b');
    expect(normalizeName('a{b}', 'fb')).toBe('a-b');
    expect(normalizeName('a<b>', 'fb')).toBe('a-b');
  });

  test('given control characters, should strip them', () => {
    expect(normalizeName('test\x01name', 'fb')).toBe('testname');
    expect(normalizeName('test\x7fname', 'fb')).toBe('testname');
    expect(normalizeName('\x00\x1f', 'fb')).toBe('fb');
  });

  test('given double dots, should collapse to single dot', () => {
    expect(normalizeName('a..b', 'fb')).toBe('a.b');
    expect(normalizeName('a...b', 'fb')).toBe('a.b');
  });

  test('given .lock suffix, should strip it', () => {
    expect(normalizeName('branch.lock', 'fb')).toBe('branch');
    expect(normalizeName('my-feature.lock', 'fb')).toBe('my-feature');
  });

  test('given double .lock suffix, should strip both', () => {
    expect(normalizeName('test.lock.lock', 'fb')).toBe('test');
  });

  test('given .lock after transform cleanup, should strip it', () => {
    expect(normalizeName('test-.lock', 'fb')).toBe('test');
  });

  test('given leading/trailing hyphens and dots, should strip them', () => {
    expect(normalizeName('-leading', 'fb')).toBe('leading');
    expect(normalizeName('trailing-', 'fb')).toBe('trailing');
    expect(normalizeName('.leading', 'fb')).toBe('leading');
    expect(normalizeName('trailing.', 'fb')).toBe('trailing');
    expect(normalizeName('--double--', 'fb')).toBe('double');
  });

  test('given consecutive hyphens, should collapse to single', () => {
    expect(normalizeName('a---b', 'fb')).toBe('a-b');
  });

  test('given double slashes, should collapse to single slash', () => {
    expect(normalizeName('a//b', 'fb')).toBe('a/b');
  });

  test('given leading/trailing slashes, should strip them', () => {
    expect(normalizeName('/name', 'fb')).toBe('name');
    expect(normalizeName('name/', 'fb')).toBe('name');
    expect(normalizeName('/name/', 'fb')).toBe('name');
  });

  test('given empty string, should return fallback', () => {
    expect(normalizeName('', 'wt-abc123')).toBe('wt-abc123');
  });

  test('given only invalid chars, should return fallback', () => {
    expect(normalizeName('~^:?*', 'wt-abc123')).toBe('wt-abc123');
  });

  test('given already valid name, should pass through', () => {
    expect(normalizeName('my-feature', 'fb')).toBe('my-feature');
    expect(normalizeName('fix-123', 'fb')).toBe('fix-123');
  });

  test('given composite real-world names, should normalize correctly', () => {
    expect(normalizeName('Fix Login Bug', 'fb')).toBe('fix-login-bug');
    expect(normalizeName('feature/auth-flow', 'fb')).toBe('feature/auth-flow');
    expect(normalizeName('JIRA-1234 Fix Auth', 'fb')).toBe('jira-1234-fix-auth');
  });

  test('given unicode input, should pass through valid chars', () => {
    expect(normalizeName('café-résumé', 'fb')).toBe('café-résumé');
  });

  test('given leading dot in a segment, should strip it', () => {
    expect(normalizeName('a/.b', 'fb')).toBe('a/b');
    expect(normalizeName('a/.hidden/b', 'fb')).toBe('a/hidden/b');
  });

  test('given .lock suffix in a mid-path segment, should strip it', () => {
    expect(normalizeName('foo.lock/bar', 'fb')).toBe('foo/bar');
    expect(normalizeName('a/b.lock/c', 'fb')).toBe('a/b/c');
  });

  test('given segment that normalizes to empty, should drop it', () => {
    expect(normalizeName('a/.lock/b', 'fb')).toBe('a/b');
    expect(normalizeName('a/---/b', 'fb')).toBe('a/b');
  });
});
