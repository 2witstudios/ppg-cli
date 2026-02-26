import { execa } from 'execa';
import { execaEnv } from '../lib/env.js';

export type PrState = 'MERGED' | 'OPEN' | 'CLOSED' | 'UNKNOWN';

/**
 * Check the GitHub PR state for a given branch.
 * Uses `gh pr view` to query the PR associated with the branch.
 * Returns 'UNKNOWN' if gh is not available or the command fails.
 */
export async function checkPrState(branch: string): Promise<PrState> {
  try {
    const result = await execa(
      'gh',
      ['pr', 'view', branch, '--json', 'state', '--jq', '.state'],
      execaEnv,
    );
    const state = result.stdout.trim().toUpperCase();
    if (state === 'MERGED' || state === 'OPEN' || state === 'CLOSED') {
      return state;
    }
    return 'UNKNOWN';
  } catch {
    return 'UNKNOWN';
  }
}
