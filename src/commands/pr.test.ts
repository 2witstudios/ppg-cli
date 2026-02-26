import { describe, test, expect } from 'vitest';

import { buildBodyFromResults, truncateBody } from './pr.js';

describe('truncateBody', () => {
  test('given body within limit, should return unchanged', () => {
    const body = 'Short body text';
    expect(truncateBody(body)).toBe(body);
  });

  test('given body at exactly 60000 chars, should return unchanged', () => {
    const body = 'x'.repeat(60_000);
    expect(truncateBody(body)).toBe(body);
  });

  test('given body exceeding limit, should truncate with notice', () => {
    const body = 'x'.repeat(70_000);
    const result = truncateBody(body);

    expect(result.length).toBeLessThan(body.length);
    expect(result).toContain('[Truncated');
    expect(result).toContain('.ppg/results/');
    expect(result.startsWith('x'.repeat(60_000))).toBe(true);
  });

  test('given very large body, should truncate to manageable size', () => {
    const body = 'a'.repeat(200_000);
    const result = truncateBody(body);

    // Should be roughly MAX_BODY_LENGTH + truncation notice
    expect(result.length).toBeLessThan(61_000);
  });
});

describe('buildBodyFromResults', () => {
  test('given no agents, should return empty string', async () => {
    const result = await buildBodyFromResults([]);
    expect(result).toBe('');
  });

  test('given single agent, should return formatted section', async () => {
    const agents = [{ id: 'ag-1', prompt: 'Fix the bug' }];
    const result = await buildBodyFromResults(agents);

    expect(result).toContain('## Agent: ag-1');
    expect(result).toContain('Fix the bug');
  });

  test('given multiple agents, should join with separator', async () => {
    const agents = [
      { id: 'ag-1', prompt: 'Task 1' },
      { id: 'ag-2', prompt: 'Task 2' },
    ];
    const result = await buildBodyFromResults(agents);

    expect(result).toContain('## Agent: ag-1');
    expect(result).toContain('Task 1');
    expect(result).toContain('---');
    expect(result).toContain('## Agent: ag-2');
    expect(result).toContain('Task 2');
  });

  test('given large prompts exceeding limit, should truncate', async () => {
    const agents = [{ id: 'ag-1', prompt: 'x'.repeat(100_000) }];
    const result = await buildBodyFromResults(agents);

    expect(result.length).toBeLessThan(61_000);
    expect(result).toContain('[Truncated');
  });
});
