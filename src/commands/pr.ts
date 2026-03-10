import { updateManifest, resolveWorktree } from '../core/manifest.js';
import { refreshAllAgentStatuses } from '../core/agent.js';
import { getRepoRoot } from '../core/worktree.js';
import { createWorktreePr } from '../core/pr.js';
import { NotInitializedError, WorktreeNotFoundError } from '../lib/errors.js';
import { output, success, info } from '../lib/output.js';

// Re-export for backwards compatibility with existing tests/consumers
export { buildBodyFromResults, truncateBody } from '../core/pr.js';

export interface PrOptions {
  title?: string;
  body?: string;
  draft?: boolean;
  json?: boolean;
}

export async function prCommand(worktreeRef: string, options: PrOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  let manifest;
  try {
    manifest = await updateManifest(projectRoot, async (m) => {
      return refreshAllAgentStatuses(m, projectRoot);
    });
  } catch {
    throw new NotInitializedError(projectRoot);
  }

  const wt = resolveWorktree(manifest, worktreeRef);
  if (!wt) throw new WorktreeNotFoundError(worktreeRef);

  info(`Creating PR for ${wt.branch}`);
  const result = await createWorktreePr(projectRoot, wt, {
    title: options.title,
    body: options.body,
    draft: options.draft,
  });

  if (options.json) {
    output({ success: true, ...result }, true);
  } else {
    success(`PR created: ${result.prUrl}`);
  }
}
