import { readManifest, updateManifest, findAgent, resolveWorktree } from '../core/manifest.js';
import { killAgent, killAgents } from '../core/agent.js';
import { getRepoRoot } from '../core/worktree.js';
import { cleanupWorktree } from '../core/cleanup.js';
import { getCurrentPaneId, excludeSelf } from '../core/self.js';
import { listSessionPanes, type PaneInfo } from '../core/tmux.js';
import { PgError, NotInitializedError, AgentNotFoundError, WorktreeNotFoundError } from '../lib/errors.js';
import { output, success, info, warn } from '../lib/output.js';
import type { AgentEntry } from '../types/manifest.js';

export interface KillOptions {
  agent?: string;
  worktree?: string;
  all?: boolean;
  remove?: boolean;
  delete?: boolean;
  json?: boolean;
}

export async function killCommand(options: KillOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  if (!options.agent && !options.worktree && !options.all) {
    throw new PgError('One of --agent, --worktree, or --all is required', 'INVALID_ARGS');
  }

  // Capture self-identification once at the start
  const selfPaneId = getCurrentPaneId();
  let paneMap: Map<string, PaneInfo> | undefined;
  if (selfPaneId) {
    const manifest = await readManifest(projectRoot);
    paneMap = await listSessionPanes(manifest.sessionName);
  }

  if (options.agent) {
    await killSingleAgent(projectRoot, options.agent, options, selfPaneId, paneMap);
  } else if (options.worktree) {
    await killWorktreeAgents(projectRoot, options.worktree, options, selfPaneId, paneMap);
  } else if (options.all) {
    await killAllAgents(projectRoot, options, selfPaneId, paneMap);
  }
}

async function killSingleAgent(
  projectRoot: string,
  agentId: string,
  options: KillOptions,
  selfPaneId: string | null,
  paneMap?: Map<string, PaneInfo>,
): Promise<void> {
  const manifest = await readManifest(projectRoot);
  const found = findAgent(manifest, agentId);
  if (!found) throw new AgentNotFoundError(agentId);

  const { agent } = found;
  const isTerminal = ['completed', 'failed', 'killed', 'lost'].includes(agent.status);

  // Self-protection check
  if (selfPaneId && paneMap) {
    const { skipped } = excludeSelf([agent], selfPaneId, paneMap);
    if (skipped.length > 0) {
      warn(`Cannot kill agent ${agentId} — it contains the current ppg process`);
      if (options.json) {
        output({ success: false, skipped: [agentId], reason: 'self-protection' }, true);
      }
      return;
    }
  }

  if (options.delete) {
    // For --delete: skip kill if already in terminal state, just clean up
    if (!isTerminal) {
      info(`Killing agent ${agentId}`);
      await killAgent(agent);
    }
    // Kill the tmux pane explicitly (handles already-dead)
    await import('../core/tmux.js').then((tmux) => tmux.killPane(agent.tmuxTarget));

    await updateManifest(projectRoot, (m) => {
      const f = findAgent(m, agentId);
      if (f) {
        delete f.worktree.agents[agentId];
      }
      return m;
    });

    if (options.json) {
      output({ success: true, killed: [agentId], deleted: [agentId] }, true);
    } else {
      success(`Deleted agent ${agentId}`);
    }
  } else {
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
}

async function killWorktreeAgents(
  projectRoot: string,
  worktreeRef: string,
  options: KillOptions,
  selfPaneId: string | null,
  paneMap?: Map<string, PaneInfo>,
): Promise<void> {
  const manifest = await readManifest(projectRoot);
  const wt = resolveWorktree(manifest, worktreeRef);

  if (!wt) throw new WorktreeNotFoundError(worktreeRef);

  let toKill = Object.values(wt.agents)
    .filter((a) => ['running', 'spawning', 'waiting'].includes(a.status));

  // Self-protection: filter out agents that would kill the current process
  const skippedIds: string[] = [];
  if (selfPaneId && paneMap) {
    const { safe, skipped } = excludeSelf(toKill, selfPaneId, paneMap);
    toKill = safe;
    for (const a of skipped) {
      skippedIds.push(a.id);
      warn(`Skipping agent ${a.id} — contains current ppg process`);
    }
  }

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

  // --delete implies --remove (always clean up worktree)
  const shouldRemove = options.remove || options.delete;
  if (shouldRemove) {
    await removeWorktreeCleanup(projectRoot, wt.id, selfPaneId, paneMap);
  }

  // --delete also removes the worktree entry from manifest
  if (options.delete) {
    await updateManifest(projectRoot, (m) => {
      delete m.worktrees[wt.id];
      return m;
    });
  }

  if (options.json) {
    output({
      success: true,
      killed: killedIds,
      skipped: skippedIds.length > 0 ? skippedIds : undefined,
      removed: shouldRemove ? [wt.id] : [],
      deleted: options.delete ? [wt.id] : [],
    }, true);
  } else {
    success(`Killed ${killedIds.length} agent(s) in worktree ${wt.id}`);
    if (skippedIds.length > 0) {
      warn(`Skipped ${skippedIds.length} agent(s) due to self-protection`);
    }
    if (options.delete) {
      success(`Deleted worktree ${wt.id}`);
    } else if (options.remove) {
      success(`Removed worktree ${wt.id}`);
    }
  }
}

async function killAllAgents(
  projectRoot: string,
  options: KillOptions,
  selfPaneId: string | null,
  paneMap?: Map<string, PaneInfo>,
): Promise<void> {
  const manifest = await readManifest(projectRoot);
  let toKill: AgentEntry[] = [];

  for (const wt of Object.values(manifest.worktrees)) {
    for (const agent of Object.values(wt.agents)) {
      if (['running', 'spawning', 'waiting'].includes(agent.status)) {
        toKill.push(agent);
      }
    }
  }

  // Self-protection: filter out agents that would kill the current process
  const skippedIds: string[] = [];
  if (selfPaneId && paneMap) {
    const { safe, skipped } = excludeSelf(toKill, selfPaneId, paneMap);
    toKill = safe;
    for (const a of skipped) {
      skippedIds.push(a.id);
      warn(`Skipping agent ${a.id} — contains current ppg process`);
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

  // --delete implies --remove
  const shouldRemove = options.remove || options.delete;
  if (shouldRemove) {
    for (const wtId of activeWorktreeIds) {
      await removeWorktreeCleanup(projectRoot, wtId, selfPaneId, paneMap);
    }
  }

  // --delete also removes worktree entries from manifest
  if (options.delete) {
    await updateManifest(projectRoot, (m) => {
      for (const wtId of activeWorktreeIds) {
        delete m.worktrees[wtId];
      }
      return m;
    });
  }

  if (options.json) {
    output({
      success: true,
      killed: killedIds,
      skipped: skippedIds.length > 0 ? skippedIds : undefined,
      removed: shouldRemove ? activeWorktreeIds : [],
      deleted: options.delete ? activeWorktreeIds : [],
    }, true);
  } else {
    success(`Killed ${killedIds.length} agent(s) across ${activeWorktreeIds.length} worktree(s)`);
    if (skippedIds.length > 0) {
      warn(`Skipped ${skippedIds.length} agent(s) due to self-protection`);
    }
    if (options.delete) {
      success(`Deleted ${activeWorktreeIds.length} worktree(s)`);
    } else if (options.remove) {
      success(`Removed ${activeWorktreeIds.length} worktree(s)`);
    }
  }
}

async function removeWorktreeCleanup(
  projectRoot: string,
  wtId: string,
  selfPaneId: string | null,
  paneMap?: Map<string, PaneInfo>,
): Promise<void> {
  const manifest = await readManifest(projectRoot);
  const wt = resolveWorktree(manifest, wtId);
  if (!wt) return;
  await cleanupWorktree(projectRoot, wt, {
    selfPaneId,
    paneMap,
  });
}
