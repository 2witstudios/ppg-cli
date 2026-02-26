import { requireManifest, updateManifest, resolveWorktree } from '../core/manifest.js';
import { refreshAllAgentStatuses } from '../core/agent.js';
import { getRepoRoot } from '../core/worktree.js';
import { PpgError, WorktreeNotFoundError } from '../lib/errors.js';
import { output, info } from '../lib/output.js';
import type { AgentEntry, AgentStatus, Manifest } from '../types/manifest.js';

export interface WaitOptions {
  all?: boolean;
  timeout?: number;
  interval?: number;
  json?: boolean;
}

const TERMINAL_STATUSES: AgentStatus[] = ['completed', 'failed', 'killed', 'lost'];

export async function waitCommand(worktreeRef: string | undefined, options: WaitOptions): Promise<void> {
  const projectRoot = await getRepoRoot();
  const interval = (options.interval ?? 5) * 1000;
  const timeout = options.timeout ? options.timeout * 1000 : undefined;
  const startTime = Date.now();

  if (!worktreeRef && !options.all) {
    throw new PpgError('Specify a worktree ID or use --all', 'INVALID_ARGS');
  }

  if (!options.json) {
    info('Waiting for agents to complete...');
  }

  while (true) {
    // Check timeout
    if (timeout && (Date.now() - startTime) >= timeout) {
      const manifest = await refreshAndGet(projectRoot);
      const agents = collectAgents(manifest, worktreeRef, options.all);
      if (options.json) {
        output({
          timedOut: true,
          agents: agents.map(formatAgent),
        }, true);
      }
      throw new PpgError('Timed out waiting for agents', 'WAIT_TIMEOUT', 2);
    }

    const manifest = await refreshAndGet(projectRoot);
    const agents = collectAgents(manifest, worktreeRef, options.all);
    const allTerminal = agents.every((a) => TERMINAL_STATUSES.includes(a.status));

    if (allTerminal) {
      const anyFailed = agents.some((a) => ['failed', 'lost'].includes(a.status));

      if (options.json) {
        output({
          timedOut: false,
          agents: agents.map(formatAgent),
        }, true);
      } else {
        for (const a of agents) {
          info(`  ${a.id}: ${a.status}`);
        }
      }

      if (anyFailed) {
        throw new PpgError('Some agents failed', 'AGENTS_FAILED', 1);
      }
      return;
    }

    // Wait before next poll
    await new Promise((resolve) => setTimeout(resolve, interval));
  }
}

async function refreshAndGet(projectRoot: string): Promise<Manifest> {
  await requireManifest(projectRoot);
  return await updateManifest(projectRoot, async (m) => {
    return refreshAllAgentStatuses(m, projectRoot);
  });
}

function collectAgents(
  manifest: Manifest,
  worktreeRef: string | undefined,
  all?: boolean,
): AgentEntry[] {
  if (all) {
    const agents: AgentEntry[] = [];
    for (const wt of Object.values(manifest.worktrees)) {
      agents.push(...Object.values(wt.agents));
    }
    return agents;
  }

  const wt = resolveWorktree(manifest, worktreeRef!);
  if (!wt) throw new WorktreeNotFoundError(worktreeRef!);
  return Object.values(wt.agents);
}

function formatAgent(a: AgentEntry) {
  return {
    id: a.id,
    status: a.status,
    agentType: a.agentType,
    exitCode: a.exitCode,
    startedAt: a.startedAt,
    completedAt: a.completedAt,
  };
}
