import { execa } from 'execa';
import { execaEnv } from '../lib/env.js';
import { PpgError, GhNotFoundError } from '../lib/errors.js';
import { updateManifest } from './manifest.js';
import type { WorktreeEntry } from '../types/manifest.js';

export type PrState = 'MERGED' | 'OPEN' | 'CLOSED' | 'UNKNOWN';

// GitHub PR body limit is 65536 chars; leave room for truncation notice
const MAX_BODY_LENGTH = 60_000;

/** Build PR body from agent prompts, with truncation. */
export async function buildBodyFromResults(agents: { id: string; prompt: string }[]): Promise<string> {
  if (agents.length === 0) return '';
  const sections = agents.map((a) => `## Agent: ${a.id}\n\n${a.prompt}`);
  return truncateBody(sections.join('\n\n---\n\n'));
}

/** Truncate body to stay within GitHub's PR body size limit. */
export function truncateBody(body: string): string {
  if (body.length <= MAX_BODY_LENGTH) return body;
  return body.slice(0, MAX_BODY_LENGTH) + '\n\n---\n\n*[Truncated — full results available in `.ppg/results/`]*';
}

export interface CreatePrOptions {
  title?: string;
  body?: string;
  draft?: boolean;
}

export interface CreatePrResult {
  worktreeId: string;
  branch: string;
  baseBranch: string;
  prUrl: string;
}

/** Push branch and create a GitHub PR for a worktree. Stores prUrl in manifest. */
export async function createWorktreePr(
  projectRoot: string,
  wt: WorktreeEntry,
  options: CreatePrOptions = {},
): Promise<CreatePrResult> {
  // Verify gh is available
  try {
    await execa('gh', ['--version'], execaEnv);
  } catch {
    throw new GhNotFoundError();
  }

  // Push the worktree branch
  try {
    await execa('git', ['push', '-u', 'origin', wt.branch], { ...execaEnv, cwd: projectRoot });
  } catch (err) {
    throw new PpgError(
      `Failed to push branch ${wt.branch}: ${err instanceof Error ? err.message : err}`,
      'INVALID_ARGS',
    );
  }

  // Build PR title and body
  const prTitle = options.title ?? wt.name;
  const prBody = options.body ?? await buildBodyFromResults(Object.values(wt.agents));

  // Build gh pr create args
  const ghArgs = [
    'pr', 'create',
    '--head', wt.branch,
    '--base', wt.baseBranch,
    '--title', prTitle,
    '--body', prBody,
  ];
  if (options.draft) {
    ghArgs.push('--draft');
  }

  let prUrl: string;
  try {
    const result = await execa('gh', ghArgs, { ...execaEnv, cwd: projectRoot });
    prUrl = result.stdout.trim();
  } catch (err) {
    throw new PpgError(
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

  return {
    worktreeId: wt.id,
    branch: wt.branch,
    baseBranch: wt.baseBranch,
    prUrl,
  };
}

/**
 * Check the GitHub PR state for a given branch.
 * Uses `gh pr view` to query the PR associated with the branch.
 * Returns 'UNKNOWN' if gh is not available or the command fails.
 */
export async function checkPrState(branch: string): Promise<PrState> {
  try {
    const result = await execa(
      'gh',
      ['pr', 'view', branch, '--json', 'state', '--jq', '.state'],
      execaEnv,
    );
    const state = result.stdout.trim().toUpperCase();
    if (state === 'MERGED' || state === 'OPEN' || state === 'CLOSED') {
      return state;
    }
    return 'UNKNOWN';
  } catch {
    return 'UNKNOWN';
  }
}
