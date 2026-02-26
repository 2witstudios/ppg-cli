import { loadConfig } from '../core/config.js';
import { requireManifest, updateManifest } from '../core/manifest.js';
import { getRepoRoot, getCurrentBranch, createWorktree, adoptWorktree } from '../core/worktree.js';
import { setupWorktreeEnv } from '../core/env.js';
import { worktreeId as genWorktreeId } from '../lib/id.js';
import { PpgError } from '../lib/errors.js';
import { output, success, info } from '../lib/output.js';
import { normalizeName } from '../lib/name.js';
import type { WorktreeEntry } from '../types/manifest.js';

export interface WorktreeCreateOptions {
  name?: string;
  base?: string;
  branch?: string;
  json?: boolean;
}

export async function worktreeCreateCommand(options: WorktreeCreateOptions): Promise<void> {
  // Validate conflicting flags
  if (options.branch && options.base) {
    throw new PpgError('--branch and --base are mutually exclusive (--base is for new branches)', 'INVALID_ARGS');
  }

  const projectRoot = await getRepoRoot();
  const config = await loadConfig(projectRoot);

  // Verify initialized
  await requireManifest(projectRoot);

  const wtId = genWorktreeId();
  let name: string;
  let branchName: string;
  let baseBranch: string;
  let wtPath: string;

  if (options.branch) {
    // Adopt an existing branch
    branchName = options.branch;
    const derivedName = branchName.startsWith('ppg/') ? branchName.slice(4) : branchName;
    name = options.name ? normalizeName(options.name, wtId) : normalizeName(derivedName, wtId);
    baseBranch = await getCurrentBranch(projectRoot);

    info(`Creating worktree ${wtId} from existing branch ${branchName}`);
    wtPath = await adoptWorktree(projectRoot, wtId, branchName);
  } else {
    // Create a new branch
    baseBranch = options.base ?? await getCurrentBranch(projectRoot);
    name = options.name ? normalizeName(options.name, wtId) : wtId;
    branchName = `ppg/${name}`;

    info(`Creating worktree ${wtId} on branch ${branchName}`);
    wtPath = await createWorktree(projectRoot, wtId, {
      branch: branchName,
      base: baseBranch,
    });
  }

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
