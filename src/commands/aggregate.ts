import fs from 'node:fs/promises';
import { requireManifest, resolveWorktree, updateManifest } from '../core/manifest.js';
import { refreshAllAgentStatuses } from '../core/agent.js';
import { getRepoRoot } from '../core/worktree.js';
import * as tmux from '../core/tmux.js';
import { WorktreeNotFoundError } from '../lib/errors.js';
import { output, success, warn } from '../lib/output.js';
import type { AgentEntry, WorktreeEntry } from '../types/manifest.js';

export interface AggregateOptions {
  all?: boolean;
  output?: string;
  json?: boolean;
}

export async function aggregateCommand(
  worktreeId?: string,
  options?: AggregateOptions,
): Promise<void> {
  const projectRoot = await getRepoRoot();

  await requireManifest(projectRoot);
  const manifest = await updateManifest(projectRoot, async (m) => {
    return refreshAllAgentStatuses(m, projectRoot);
  });

  let worktrees: WorktreeEntry[];

  if (options?.all) {
    worktrees = Object.values(manifest.worktrees);
  } else if (worktreeId) {
    const wt = resolveWorktree(manifest, worktreeId);
    if (!wt) throw new WorktreeNotFoundError(worktreeId);
    worktrees = [wt];
  } else {
    // Default: all worktrees with completed agents
    worktrees = Object.values(manifest.worktrees).filter((wt) =>
      Object.values(wt.agents).some((a) => a.status === 'completed'),
    );
  }

  const results: AggregatedResult[] = [];

  for (const wt of worktrees) {
    for (const agent of Object.values(wt.agents)) {
      if (agent.status !== 'completed' && agent.status !== 'failed') continue;

      const result = await collectAgentResult(agent, projectRoot);
      results.push({
        agentId: agent.id,
        worktreeId: wt.id,
        worktreeName: wt.name,
        branch: wt.branch,
        status: agent.status,
        content: result,
      });
    }
  }

  if (results.length === 0) {
    if (options?.json) {
      output({ results: [] }, true);
    } else {
      console.log('No completed agent results to aggregate.');
    }
    return;
  }

  if (options?.json) {
    output({ results }, true);
    return;
  }

  // Build combined document
  const combined = results.map((r) => {
    return [
      `# Agent: ${r.agentId}`,
      `**Worktree:** ${r.worktreeName} (${r.worktreeId})`,
      `**Branch:** ${r.branch}`,
      `**Status:** ${r.status}`,
      '',
      r.content,
      '',
      '---',
      '',
    ].join('\n');
  }).join('\n');

  if (options?.output) {
    await fs.writeFile(options.output, combined, 'utf-8');
    success(`Wrote ${results.length} result(s) to ${options.output}`);
  } else {
    console.log(combined);
  }
}

interface AggregatedResult {
  agentId: string;
  worktreeId: string;
  worktreeName: string;
  branch: string;
  status: string;
  content: string;
}

async function collectAgentResult(
  agent: AgentEntry,
  projectRoot: string,
): Promise<string> {
  // Try reading result file first
  try {
    const content = await fs.readFile(agent.resultFile, 'utf-8');
    return content;
  } catch {
    // No result file
  }

  // Fallback: capture pane content
  try {
    const paneContent = await tmux.capturePane(agent.tmuxTarget, 500);
    return `*[No result file — pane capture fallback]*\n\n\`\`\`\n${paneContent}\n\`\`\``;
  } catch {
    return '*[No result file and pane not available]*';
  }
}
