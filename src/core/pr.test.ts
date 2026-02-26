import { describe, test, expect, vi, beforeEach } from 'vitest';
import { checkPrState } from './pr.js';

vi.mock('execa', () => ({
  execa: vi.fn(),
}));

describe('checkPrState', () => {
  let mockExeca: ReturnType<typeof vi.fn>;

  beforeEach(async () => {
    vi.clearAllMocks();
    const { execa } = await import('execa');
    mockExeca = execa as unknown as ReturnType<typeof vi.fn>;
  });

  test('returns OPEN when PR is open', async () => {
    mockExeca.mockResolvedValueOnce({ stdout: 'OPEN' });
    const state = await checkPrState('pogu/my-feature');
    expect(state).toBe('OPEN');
    expect(mockExeca).toHaveBeenCalledWith(
      'gh',
      ['pr', 'view', 'pogu/my-feature', '--json', 'state', '--jq', '.state'],
      expect.any(Object),
    );
  });

  test('returns MERGED when PR is merged', async () => {
    mockExeca.mockResolvedValueOnce({ stdout: 'MERGED' });
    const state = await checkPrState('pogu/my-feature');
    expect(state).toBe('MERGED');
  });

  test('returns CLOSED when PR is closed', async () => {
    mockExeca.mockResolvedValueOnce({ stdout: 'CLOSED' });
    const state = await checkPrState('pogu/my-feature');
    expect(state).toBe('CLOSED');
  });

  test('returns UNKNOWN when gh command fails', async () => {
    mockExeca.mockRejectedValueOnce(new Error('gh not found'));
    const state = await checkPrState('pogu/my-feature');
    expect(state).toBe('UNKNOWN');
  });

  test('returns UNKNOWN for unexpected output', async () => {
    mockExeca.mockResolvedValueOnce({ stdout: 'SOMETHING_ELSE' });
    const state = await checkPrState('pogu/my-feature');
    expect(state).toBe('UNKNOWN');
  });

  test('handles lowercase state from gh', async () => {
    mockExeca.mockResolvedValueOnce({ stdout: 'open' });
    const state = await checkPrState('pogu/my-feature');
    expect(state).toBe('OPEN');
  });

  test('handles whitespace in output', async () => {
    mockExeca.mockResolvedValueOnce({ stdout: '  MERGED\n' });
    const state = await checkPrState('pogu/my-feature');
    expect(state).toBe('MERGED');
  });
});
