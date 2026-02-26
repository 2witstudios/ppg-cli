import fs from 'node:fs/promises';
import { execa } from 'execa';
import { updateManifest, resolveWorktree } from '../core/manifest.js';
import { refreshAllAgentStatuses } from '../core/agent.js';
import { getRepoRoot } from '../core/worktree.js';
import { PoguError, NotInitializedError, WorktreeNotFoundError, GhNotFoundError } from '../lib/errors.js';
import { output, success, info } from '../lib/output.js';
import { execaEnv } from '../lib/env.js';

// GitHub PR body limit is 65536 chars; leave room for truncation notice
const MAX_BODY_LENGTH = 60_000;

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

  // Verify gh is available
  try {
    await execa('gh', ['--version'], execaEnv);
  } catch {
    throw new GhNotFoundError();
  }

  // Push the worktree branch
  info(`Pushing branch ${wt.branch} to origin`);
  try {
    await execa('git', ['push', '-u', 'origin', wt.branch], { ...execaEnv, cwd: projectRoot });
  } catch (err) {
    throw new PoguError(
      `Failed to push branch ${wt.branch}: ${err instanceof Error ? err.message : err}`,
      'INVALID_ARGS',
    );
  }

  // Build PR title and body
  const title = options.title ?? wt.name;
  const body = options.body ?? await buildBodyFromResults(Object.values(wt.agents));

  // Build gh pr create args
  const ghArgs = [
    'pr', 'create',
    '--head', wt.branch,
    '--base', wt.baseBranch,
    '--title', title,
    '--body', body,
  ];
  if (options.draft) {
    ghArgs.push('--draft');
  }

  info(`Creating PR: ${title}`);
  let prUrl: string;
  try {
    const result = await execa('gh', ghArgs, { ...execaEnv, cwd: projectRoot });
    prUrl = result.stdout.trim();
  } catch (err) {
    throw new PoguError(
      `Failed to create PR: ${err instanceof Error ? err.message : err}`,
      'INVALID_ARGS',
    );
  }

  // Store PR URL in manifest
  await updateManifest(projectRoot, (m) => {
    if (m.worktrees[wt.id]) {
      m.worktrees[wt.id].prUrl = prUrl;
    }
    return m;
  });

  if (options.json) {
    output({
      success: true,
      worktreeId: wt.id,
      branch: wt.branch,
      baseBranch: wt.baseBranch,
      prUrl,
    }, true);
  } else {
    success(`PR created: ${prUrl}`);
  }
}

/** Read agent result files and join them into a PR body, with truncation. */
export async function buildBodyFromResults(agents: { resultFile: string }[]): Promise<string> {
  const reads = agents.map(async (agent) => {
    try {
      return await fs.readFile(agent.resultFile, 'utf-8');
    } catch {
      return null;
    }
  });
  const contents = (await Promise.all(reads)).filter((c): c is string => c !== null);
  if (contents.length === 0) return '';
  return truncateBody(contents.join('\n\n---\n\n'));
}

/** Truncate body to stay within GitHub's PR body size limit. */
export function truncateBody(body: string): string {
  if (body.length <= MAX_BODY_LENGTH) return body;
  return body.slice(0, MAX_BODY_LENGTH) + '\n\n---\n\n*[Truncated — full results available in `.pogu/results/`]*';
}
