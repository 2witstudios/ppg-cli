import { describe, test, expect } from 'vitest';
import { worktreeId, agentId, sessionId } from './id.js';

describe('worktreeId', () => {
  test('matches wt-{6 lowercase alphanumeric}', () => {
    const id = worktreeId();
    expect(id).toMatch(/^wt-[a-z0-9]{6}$/);
  });

  test('generates unique ids', () => {
    const ids = new Set(Array.from({ length: 50 }, () => worktreeId()));
    expect(ids.size).toBe(50);
  });
});

describe('agentId', () => {
  test('matches ag-{8 lowercase alphanumeric}', () => {
    const id = agentId();
    expect(id).toMatch(/^ag-[a-z0-9]{8}$/);
  });

  test('generates unique ids', () => {
    const ids = new Set(Array.from({ length: 50 }, () => agentId()));
    expect(ids.size).toBe(50);
  });
});

describe('sessionId', () => {
  test('returns a valid UUID', () => {
    const id = sessionId();
    expect(id).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    );
  });

  test('generates unique ids', () => {
    const ids = new Set(Array.from({ length: 50 }, () => sessionId()));
    expect(ids.size).toBe(50);
  });
});
