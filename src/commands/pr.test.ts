import { describe, test, expect, vi, beforeEach } from 'vitest';
import fs from 'node:fs/promises';

vi.mock('node:fs/promises', () => ({
  default: {
    readFile: vi.fn(),
  },
}));

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
    expect(result).toContain('.pg/results/');
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
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test('given no agents, should return empty string', async () => {
    const result = await buildBodyFromResults([]);
    expect(result).toBe('');
  });

  test('given agents with no result files, should return empty string', async () => {
    vi.mocked(fs.readFile).mockRejectedValue(new Error('ENOENT'));

    const agents = [
      { resultFile: '/tmp/results/ag-1.md' },
      { resultFile: '/tmp/results/ag-2.md' },
    ];
    const result = await buildBodyFromResults(agents);

    expect(result).toBe('');
  });

  test('given single agent with result, should return its content', async () => {
    vi.mocked(fs.readFile).mockResolvedValueOnce('## Results\nTask completed.');

    const agents = [{ resultFile: '/tmp/results/ag-1.md' }];
    const result = await buildBodyFromResults(agents);

    expect(result).toBe('## Results\nTask completed.');
  });

  test('given multiple agents with results, should join with separator', async () => {
    vi.mocked(fs.readFile)
      .mockResolvedValueOnce('Agent 1 results')
      .mockResolvedValueOnce('Agent 2 results');

    const agents = [
      { resultFile: '/tmp/results/ag-1.md' },
      { resultFile: '/tmp/results/ag-2.md' },
    ];
    const result = await buildBodyFromResults(agents);

    expect(result).toBe('Agent 1 results\n\n---\n\nAgent 2 results');
  });

  test('given mixed results (some missing), should include only available', async () => {
    vi.mocked(fs.readFile)
      .mockResolvedValueOnce('Agent 1 results')
      .mockRejectedValueOnce(new Error('ENOENT'))
      .mockResolvedValueOnce('Agent 3 results');

    const agents = [
      { resultFile: '/tmp/results/ag-1.md' },
      { resultFile: '/tmp/results/ag-2.md' },
      { resultFile: '/tmp/results/ag-3.md' },
    ];
    const result = await buildBodyFromResults(agents);

    expect(result).toBe('Agent 1 results\n\n---\n\nAgent 3 results');
  });

  test('given large results exceeding limit, should truncate', async () => {
    vi.mocked(fs.readFile).mockResolvedValueOnce('x'.repeat(100_000));

    const agents = [{ resultFile: '/tmp/results/ag-1.md' }];
    const result = await buildBodyFromResults(agents);

    expect(result.length).toBeLessThan(61_000);
    expect(result).toContain('[Truncated');
  });
});
