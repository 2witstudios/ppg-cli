import { loadConfig } from '../core/config.js';
import { requireManifest, updateManifest } from '../core/manifest.js';
import { refreshAllAgentStatuses } from '../core/agent.js';
import { getRepoRoot } from '../core/worktree.js';
import { output, formatStatus, formatTable, type Column } from '../lib/output.js';
import type { AgentEntry, WorktreeEntry } from '../types/manifest.js';

export interface StatusOptions {
  json?: boolean;
  watch?: boolean;
  worktree?: string;
}

export async function statusCommand(worktreeFilter?: string, options?: StatusOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  // Read manifest and refresh statuses
  await requireManifest(projectRoot);
  const manifest = await updateManifest(projectRoot, async (m) => {
    return refreshAllAgentStatuses(m, projectRoot);
  });

  // Filter worktrees if specified
  const filter = worktreeFilter ?? options?.worktree;
  let worktrees = Object.values(manifest.worktrees);
  if (filter) {
    worktrees = worktrees.filter(
      (wt) => wt.id === filter || wt.name === filter || wt.branch === filter,
    );
  }

  if (options?.json) {
    output({
      session: manifest.sessionName,
      worktrees: Object.fromEntries(worktrees.map((wt) => [wt.id, wt])),
    }, true);
    return;
  }

  if (worktrees.length === 0) {
    console.log('No active worktrees. Use `pogu spawn` to create one.');
    return;
  }

  for (const wt of worktrees) {
    printWorktreeStatus(wt);
  }

  if (options?.watch) {
    const interval = setInterval(async () => {
      console.clear();
      try {
        const m = await updateManifest(projectRoot, async (m) => {
          return refreshAllAgentStatuses(m, projectRoot);
        });
        let wts = Object.values(m.worktrees);
        if (filter) {
          wts = wts.filter(
            (wt) => wt.id === filter || wt.name === filter || wt.branch === filter,
          );
        }
        for (const wt of wts) {
          printWorktreeStatus(wt);
        }
      } catch (err) {
        console.error('Error refreshing status:', err);
      }
    }, 2000);

    // Handle exit
    process.on('SIGINT', () => {
      clearInterval(interval);
      process.exit(0);
    });
  }
}

function printWorktreeStatus(wt: WorktreeEntry): void {
  const agents = Object.values(wt.agents);
  const statusCounts = {
    running: agents.filter((a) => a.status === 'running').length,
    completed: agents.filter((a) => a.status === 'completed').length,
    failed: agents.filter((a) => a.status === 'failed').length,
    lost: agents.filter((a) => a.status === 'lost').length,
  };

  console.log(
    `\n${wt.name} (${wt.id}) [${formatStatus(wt.status)}] branch:${wt.branch}`,
  );

  if (agents.length === 0) {
    console.log('  No agents');
    return;
  }

  const columns: Column[] = [
    { header: 'Agent', key: 'id', width: 14 },
    { header: 'Type', key: 'agentType', width: 10 },
    {
      header: 'Status',
      key: 'status',
      width: 12,
      format: (v) => formatStatus(v as AgentEntry['status']),
    },
    { header: 'Started', key: 'startedAt', width: 20, format: (v) => formatTime(v as string) },
    { header: 'Pane', key: 'tmuxTarget', width: 20 },
  ];

  const table = formatTable(agents as unknown as Record<string, unknown>[], columns);
  console.log(table.split('\n').map((l) => `  ${l}`).join('\n'));
}

function formatTime(iso: string): string {
  if (!iso) return '—';
  const d = new Date(iso);
  const now = new Date();
  const diffMs = now.getTime() - d.getTime();
  const diffMin = Math.floor(diffMs / 60_000);
  if (diffMin < 1) return 'just now';
  if (diffMin < 60) return `${diffMin}m ago`;
  const diffHr = Math.floor(diffMin / 60);
  return `${diffHr}h ${diffMin % 60}m ago`;
}
