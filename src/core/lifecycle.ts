import type { WorktreeEntry } from '../types/manifest.js';

export type WorktreeLifecycle = 'merged' | 'cleaned' | 'busy' | 'shipped' | 'idle';

export function computeLifecycle(wt: WorktreeEntry): WorktreeLifecycle {
  if (wt.status === 'merged') return 'merged';
  if (wt.status === 'cleaned') return 'cleaned';

  const agents = Object.values(wt.agents);

  if (agents.some((a) => a.status === 'running')) return 'busy';
  if (wt.prUrl) return 'shipped';

  return 'idle';
}
