import { readManifest, updateManifest, findAgent, resolveWorktree } from '../manifest.js';
import { killAgent, killAgents } from '../agent.js';
import { checkPrState } from '../pr.js';
import { cleanupWorktree } from '../cleanup.js';
import { excludeSelf } from '../self.js';
import { getBackend } from '../backend.js';
import type { PaneInfo } from '../process-manager.js';
import { PpgError, AgentNotFoundError, WorktreeNotFoundError } from '../../lib/errors.js';
import type { AgentEntry } from '../../types/manifest.js';

export interface KillInput {
  projectRoot: string;
  agent?: string;
  worktree?: string;
  all?: boolean;
  remove?: boolean;
  delete?: boolean;
  includeOpenPrs?: boolean;
  selfPaneId?: string | null;
  paneMap?: Map<string, PaneInfo>;
}

export interface KillResult {
  success: boolean;
  killed: string[];
  skipped?: string[];
  removed?: string[];
  deleted?: string[];
  skippedOpenPrs?: string[];
  worktreeCount?: number;
  message?: string;
}

export async function performKill(input: KillInput): Promise<KillResult> {
  const { projectRoot } = input;

  if (!input.agent && !input.worktree && !input.all) {
    throw new PpgError('One of --agent, --worktree, or --all is required', 'INVALID_ARGS');
  }

  if (input.agent) {
    return killSingleAgent(projectRoot, input.agent, input);
  } else if (input.worktree) {
    return killWorktreeAgents(projectRoot, input.worktree, input);
  } else {
    return killAllAgents(projectRoot, input);
  }
}

async function killSingleAgent(
  projectRoot: string,
  agentId: string,
  input: KillInput,
): Promise<KillResult> {
  const manifest = await readManifest(projectRoot);
  const found = findAgent(manifest, agentId);
  if (!found) throw new AgentNotFoundError(agentId);

  const { agent } = found;
  const isTerminal = agent.status !== 'running';

  // Self-protection check
  if (input.selfPaneId && input.paneMap) {
    const { skipped } = excludeSelf([agent], input.selfPaneId, input.paneMap);
    if (skipped.length > 0) {
      return { success: false, killed: [], skipped: [agentId], message: 'self-protection' };
    }
  }

  if (input.delete) {
    if (!isTerminal) {
      await killAgent(agent);
    }
    await getBackend().killPane(agent.tmuxTarget);

    await updateManifest(projectRoot, (m) => {
      const f = findAgent(m, agentId);
      if (f) {
        delete f.worktree.agents[agentId];
      }
      return m;
    });

    return { success: true, killed: isTerminal ? [] : [agentId], deleted: [agentId] };
  }

  if (isTerminal) {
    return { success: true, killed: [], message: `Agent ${agentId} already ${agent.status}` };
  }

  await killAgent(agent);

  await updateManifest(projectRoot, (m) => {
    const f = findAgent(m, agentId);
    if (f) {
      f.agent.status = 'gone';
    }
    return m;
  });

  return { success: true, killed: [agentId] };
}

async function killWorktreeAgents(
  projectRoot: string,
  worktreeRef: string,
  input: KillInput,
): Promise<KillResult> {
  const manifest = await readManifest(projectRoot);
  const wt = resolveWorktree(manifest, worktreeRef);
  if (!wt) throw new WorktreeNotFoundError(worktreeRef);

  let toKill = Object.values(wt.agents).filter((a) => a.status === 'running');

  const skippedIds: string[] = [];
  if (input.selfPaneId && input.paneMap) {
    const { safe, skipped } = excludeSelf(toKill, input.selfPaneId, input.paneMap);
    toKill = safe;
    for (const a of skipped) skippedIds.push(a.id);
  }

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

  // Check for open PR before deleting worktree
  let skippedOpenPr = false;
  if (input.delete && !input.includeOpenPrs) {
    const prState = await checkPrState(wt.branch);
    if (prState === 'OPEN') {
      skippedOpenPr = true;
    }
  }

  const shouldRemove = (input.remove || input.delete) && !skippedOpenPr;
  if (shouldRemove) {
    await removeWorktreeCleanup(projectRoot, wt.id, input.selfPaneId ?? null, input.paneMap);
  }

  if (input.delete && !skippedOpenPr) {
    await updateManifest(projectRoot, (m) => {
      delete m.worktrees[wt.id];
      return m;
    });
  }

  return {
    success: true,
    killed: killedIds,
    skipped: skippedIds.length > 0 ? skippedIds : undefined,
    removed: shouldRemove ? [wt.id] : [],
    deleted: (input.delete && !skippedOpenPr) ? [wt.id] : [],
    skippedOpenPrs: skippedOpenPr ? [wt.id] : undefined,
  };
}

async function killAllAgents(
  projectRoot: string,
  input: KillInput,
): Promise<KillResult> {
  const manifest = await readManifest(projectRoot);
  let toKill: AgentEntry[] = [];

  for (const wt of Object.values(manifest.worktrees)) {
    for (const agent of Object.values(wt.agents)) {
      if (agent.status === 'running') {
        toKill.push(agent);
      }
    }
  }

  const skippedIds: string[] = [];
  if (input.selfPaneId && input.paneMap) {
    const { safe, skipped } = excludeSelf(toKill, input.selfPaneId, input.paneMap);
    toKill = safe;
    for (const a of skipped) skippedIds.push(a.id);
  }

  const killedIds = toKill.map((a) => a.id);
  await killAgents(toKill);

  const activeWorktreeIds = Object.values(manifest.worktrees)
    .filter((wt) => wt.status === 'active')
    .map((wt) => wt.id);

  await updateManifest(projectRoot, (m) => {
    for (const wt of Object.values(m.worktrees)) {
      for (const agent of Object.values(wt.agents)) {
        if (killedIds.includes(agent.id)) {
          agent.status = 'gone';
        }
      }
    }
    return m;
  });

  // Filter out worktrees with open PRs
  let worktreesToRemove = activeWorktreeIds;
  const openPrWorktreeIds: string[] = [];
  if (input.delete && !input.includeOpenPrs) {
    worktreesToRemove = [];
    for (const wtId of activeWorktreeIds) {
      const wt = manifest.worktrees[wtId];
      if (wt) {
        const prState = await checkPrState(wt.branch);
        if (prState === 'OPEN') {
          openPrWorktreeIds.push(wtId);
        } else {
          worktreesToRemove.push(wtId);
        }
      }
    }
  }

  const shouldRemove = input.remove || input.delete;
  if (shouldRemove) {
    for (const wtId of worktreesToRemove) {
      await removeWorktreeCleanup(projectRoot, wtId, input.selfPaneId ?? null, input.paneMap);
    }
  }

  if (input.delete) {
    await updateManifest(projectRoot, (m) => {
      for (const wtId of worktreesToRemove) {
        delete m.worktrees[wtId];
      }
      return m;
    });
  }

  return {
    success: true,
    killed: killedIds,
    skipped: skippedIds.length > 0 ? skippedIds : undefined,
    removed: shouldRemove ? worktreesToRemove : [],
    deleted: input.delete ? worktreesToRemove : [],
    skippedOpenPrs: openPrWorktreeIds.length > 0 ? openPrWorktreeIds : undefined,
    worktreeCount: activeWorktreeIds.length,
  };
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
  await cleanupWorktree(projectRoot, wt, { selfPaneId, paneMap });
}
