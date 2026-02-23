import { readManifest, updateManifest, findAgent, resolveWorktree } from '../core/manifest.js';
import { killAgent, killAgents } from '../core/agent.js';
import { getRepoRoot } from '../core/worktree.js';
import { cleanupWorktree } from '../core/cleanup.js';
import { PgError, NotInitializedError, AgentNotFoundError, WorktreeNotFoundError } from '../lib/errors.js';
import { output, success, info } from '../lib/output.js';
import type { AgentEntry } from '../types/manifest.js';

export interface KillOptions {
  agent?: string;
  worktree?: string;
  all?: boolean;
  remove?: boolean;
  json?: boolean;
}

export async function killCommand(options: KillOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  if (!options.agent && !options.worktree && !options.all) {
    throw new PgError('One of --agent, --worktree, or --all is required', 'INVALID_ARGS');
  }

  if (options.agent) {
    await killSingleAgent(projectRoot, options.agent, options);
  } else if (options.worktree) {
    await killWorktreeAgents(projectRoot, options.worktree, options);
  } else if (options.all) {
    await killAllAgents(projectRoot, options);
  }
}

async function killSingleAgent(
  projectRoot: string,
  agentId: string,
  options: KillOptions,
): Promise<void> {
  const manifest = await readManifest(projectRoot);
  const found = findAgent(manifest, agentId);
  if (!found) throw new AgentNotFoundError(agentId);

  const { agent } = found;

  info(`Killing agent ${agentId}`);
  await killAgent(agent);

  await updateManifest(projectRoot, (m) => {
    const f = findAgent(m, agentId);
    if (f) {
      f.agent.status = 'killed';
      f.agent.completedAt = new Date().toISOString();
    }
    return m;
  });

  if (options.json) {
    output({ success: true, killed: [agentId] }, true);
  } else {
    success(`Killed agent ${agentId}`);
  }
}

async function killWorktreeAgents(
  projectRoot: string,
  worktreeRef: string,
  options: KillOptions,
): Promise<void> {
  const manifest = await readManifest(projectRoot);
  const wt = resolveWorktree(manifest, worktreeRef);

  if (!wt) throw new WorktreeNotFoundError(worktreeRef);

  const toKill = Object.values(wt.agents)
    .filter((a) => ['running', 'spawning', 'waiting'].includes(a.status));
  const killedIds = toKill.map((a) => a.id);

  for (const a of toKill) info(`Killing agent ${a.id}`);
  await killAgents(toKill);

  await updateManifest(projectRoot, (m) => {
    const mWt = m.worktrees[wt.id];
    if (mWt) {
      for (const agent of Object.values(mWt.agents)) {
        if (killedIds.includes(agent.id)) {
          agent.status = 'killed';
          agent.completedAt = new Date().toISOString();
        }
      }
    }
    return m;
  });

  if (options.remove) {
    await removeWorktreeCleanup(projectRoot, wt.id);
  }

  if (options.json) {
    output({ success: true, killed: killedIds, removed: options.remove ? [wt.id] : [] }, true);
  } else {
    success(`Killed ${killedIds.length} agent(s) in worktree ${wt.id}`);
    if (options.remove) {
      success(`Removed worktree ${wt.id}`);
    }
  }
}

async function killAllAgents(
  projectRoot: string,
  options: KillOptions,
): Promise<void> {
  const manifest = await readManifest(projectRoot);
  const toKill: AgentEntry[] = [];

  for (const wt of Object.values(manifest.worktrees)) {
    for (const agent of Object.values(wt.agents)) {
      if (['running', 'spawning', 'waiting'].includes(agent.status)) {
        toKill.push(agent);
      }
    }
  }

  const killedIds = toKill.map((a) => a.id);
  for (const a of toKill) info(`Killing agent ${a.id}`);
  await killAgents(toKill);

  // Only track active worktrees for removal (not already merged/cleaned)
  const activeWorktreeIds = Object.values(manifest.worktrees)
    .filter((wt) => wt.status === 'active')
    .map((wt) => wt.id);

  await updateManifest(projectRoot, (m) => {
    for (const wt of Object.values(m.worktrees)) {
      for (const agent of Object.values(wt.agents)) {
        if (killedIds.includes(agent.id)) {
          agent.status = 'killed';
          agent.completedAt = new Date().toISOString();
        }
      }
    }
    return m;
  });

  if (options.remove) {
    for (const wtId of activeWorktreeIds) {
      await removeWorktreeCleanup(projectRoot, wtId);
    }
  }

  if (options.json) {
    output({ success: true, killed: killedIds, removed: options.remove ? activeWorktreeIds : [] }, true);
  } else {
    success(`Killed ${killedIds.length} agent(s) across ${activeWorktreeIds.length} worktree(s)`);
    if (options.remove) {
      success(`Removed ${activeWorktreeIds.length} worktree(s)`);
    }
  }
}

async function removeWorktreeCleanup(projectRoot: string, wtId: string): Promise<void> {
  const manifest = await readManifest(projectRoot);
  const wt = resolveWorktree(manifest, wtId);
  if (!wt) return;
  await cleanupWorktree(projectRoot, wt);
}
