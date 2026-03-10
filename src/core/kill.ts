import { updateManifest } from './manifest.js';
import { killAgents } from './agent.js';
import type { WorktreeEntry } from '../types/manifest.js';

export interface KillWorktreeResult {
  worktreeId: string;
  killed: string[];
}

/** Kill all running agents in a worktree and set their status to 'gone'. */
export async function killWorktreeAgents(
  projectRoot: string,
  wt: WorktreeEntry,
): Promise<KillWorktreeResult> {
  const toKill = Object.values(wt.agents).filter((a) => a.status === 'running');
  const killedIds = toKill.map((a) => a.id);

  await killAgents(toKill);

  await updateManifest(projectRoot, (m) => {
    const mWt = m.worktrees[wt.id];
    if (mWt) {
      for (const agent of Object.values(mWt.agents)) {
        if (killedIds.includes(agent.id)) {
          agent.status = 'gone';
        }
      }
    }
    return m;
  });

  return {
    worktreeId: wt.id,
    killed: killedIds,
  };
}
