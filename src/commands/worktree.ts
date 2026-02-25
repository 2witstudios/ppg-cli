import { loadConfig } from '../core/config.js';
import { requireManifest, updateManifest } from '../core/manifest.js';
import { getRepoRoot, getCurrentBranch, createWorktree } from '../core/worktree.js';
import { setupWorktreeEnv } from '../core/env.js';
import { worktreeId as genWorktreeId } from '../lib/id.js';
import { output, success, info } from '../lib/output.js';
import { normalizeName } from '../lib/name.js';
import type { WorktreeEntry } from '../types/manifest.js';

export interface WorktreeCreateOptions {
  name?: string;
  base?: string;
  json?: boolean;
}

export async function worktreeCreateCommand(options: WorktreeCreateOptions): Promise<void> {
  const projectRoot = await getRepoRoot();
  const config = await loadConfig(projectRoot);

  // Verify initialized
  await requireManifest(projectRoot);

  const baseBranch = options.base ?? await getCurrentBranch(projectRoot);
  const wtId = genWorktreeId();
  const name = options.name ? normalizeName(options.name, wtId) : wtId;
  const branchName = `ppg/${name}`;

  // Create git worktree
  info(`Creating worktree ${wtId} on branch ${branchName}`);
  const wtPath = await createWorktree(projectRoot, wtId, {
    branch: branchName,
    base: baseBranch,
  });

  // Setup env
  await setupWorktreeEnv(projectRoot, wtPath, config);

  // Register in manifest with empty tmuxWindow and no agents
  const worktreeEntry: WorktreeEntry = {
    id: wtId,
    name,
    path: wtPath,
    branch: branchName,
    baseBranch,
    status: 'active',
    tmuxWindow: '',
    agents: {},
    createdAt: new Date().toISOString(),
  };

  await updateManifest(projectRoot, (m) => {
    m.worktrees[wtId] = worktreeEntry;
    return m;
  });

  if (options.json) {
    output({
      success: true,
      worktree: {
        id: wtId,
        name,
        branch: branchName,
        baseBranch,
        path: wtPath,
      },
    }, true);
  } else {
    success(`Created worktree ${wtId} (${name}) on branch ${branchName}`);
    info(`Path: ${wtPath}`);
    info(`Spawn agents: ppg spawn --worktree ${wtId} --prompt "your task"`);
  }
}
