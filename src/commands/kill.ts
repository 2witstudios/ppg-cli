import { performKill, type KillResult } from '../core/operations/kill.js';
import { getCurrentPaneId } from '../core/self.js';
import { readManifest } from '../core/manifest.js';
import { getRepoRoot } from '../core/worktree.js';
import { listSessionPanes } from '../core/tmux.js';
import { output, success, info, warn } from '../lib/output.js';

export interface KillOptions {
  agent?: string;
  worktree?: string;
  all?: boolean;
  remove?: boolean;
  delete?: boolean;
  includeOpenPrs?: boolean;
  json?: boolean;
}

export async function killCommand(options: KillOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  // Capture self-identification once at the start
  const selfPaneId = getCurrentPaneId();
  let paneMap: Map<string, import('../core/tmux.js').PaneInfo> | undefined;
  if (selfPaneId) {
    const manifest = await readManifest(projectRoot);
    paneMap = await listSessionPanes(manifest.sessionName);
  }

  const result = await performKill({
    projectRoot,
    agent: options.agent,
    worktree: options.worktree,
    all: options.all,
    remove: options.remove,
    delete: options.delete,
    includeOpenPrs: options.includeOpenPrs,
    selfPaneId,
    paneMap,
  });

  formatOutput(result, options);
}

function formatOutput(result: KillResult, options: KillOptions): void {
  if (options.json) {
    output(result, true);
    return;
  }

  // Emit per-agent progress for killed agents
  for (const id of result.killed) {
    info(`Killing agent ${id}`);
  }

  if (result.skipped?.length) {
    for (const id of result.skipped) {
      warn(`Skipping agent ${id} — contains current ppg process`);
    }
  }

  if (result.skippedOpenPrs?.length) {
    for (const id of result.skippedOpenPrs) {
      warn(`Skipping deletion of worktree ${id} — has open PR`);
    }
  }

  if (options.agent) {
    if (result.deleted?.length) {
      success(`Deleted agent ${options.agent}`);
    } else if (result.killed.length > 0) {
      success(`Killed agent ${options.agent}`);
    } else if (result.message) {
      info(result.message);
    }
  } else if (options.worktree) {
    if (result.killed.length > 0 || !result.skipped?.length) {
      success(`Killed ${result.killed.length} agent(s) in worktree ${options.worktree}`);
    }
    if (result.skipped?.length) {
      warn(`Skipped ${result.skipped.length} agent(s) due to self-protection`);
    }
    if (result.deleted?.length) {
      success(`Deleted worktree ${options.worktree}`);
    } else if (result.removed?.length) {
      success(`Removed worktree ${options.worktree}`);
    }
  } else if (options.all) {
    const wtMsg = result.worktreeCount !== undefined
      ? ` across ${result.worktreeCount} worktree(s)`
      : '';
    success(`Killed ${result.killed.length} agent(s)${wtMsg}`);
    if (result.skipped?.length) {
      warn(`Skipped ${result.skipped.length} agent(s) due to self-protection`);
    }
    if (result.skippedOpenPrs?.length) {
      warn(`Skipped deletion of ${result.skippedOpenPrs.length} worktree(s) with open PRs`);
    }
    if (result.deleted?.length) {
      success(`Deleted ${result.deleted.length} worktree(s)`);
    } else if (result.removed?.length) {
      success(`Removed ${result.removed.length} worktree(s)`);
    }
  }
}
