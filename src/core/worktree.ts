import { execa } from 'execa';
import { worktreePath as getWorktreePath } from '../lib/paths.js';
import { NotGitRepoError } from '../lib/errors.js';

export async function getRepoRoot(cwd?: string): Promise<string> {
  try {
    const result = await execa('git', ['rev-parse', '--show-toplevel'], {
      cwd: cwd ?? process.cwd(),
    });
    return result.stdout.trim();
  } catch {
    throw new NotGitRepoError(cwd ?? process.cwd());
  }
}

export async function getCurrentBranch(cwd?: string): Promise<string> {
  const result = await execa('git', ['branch', '--show-current'], {
    cwd: cwd ?? process.cwd(),
  });
  return result.stdout.trim();
}

export interface CreateWorktreeOptions {
  branch: string;
  base?: string;
}

export async function createWorktree(
  repoRoot: string,
  id: string,
  options: CreateWorktreeOptions,
): Promise<string> {
  const wtPath = getWorktreePath(repoRoot, id);
  const args = ['worktree', 'add', wtPath, '-b', options.branch];
  if (options.base) {
    args.push(options.base);
  }
  await execa('git', args, { cwd: repoRoot });
  return wtPath;
}

export async function removeWorktree(
  repoRoot: string,
  wtPath: string,
  options?: { force?: boolean; deleteBranch?: boolean; branchName?: string },
): Promise<void> {
  const args = ['worktree', 'remove', wtPath];
  if (options?.force) {
    args.push('--force');
  }
  await execa('git', args, { cwd: repoRoot });

  if (options?.deleteBranch && options.branchName) {
    try {
      await execa('git', ['branch', '-D', options.branchName], { cwd: repoRoot });
    } catch {
      // Branch may not exist
    }
  }
}

export async function listWorktrees(repoRoot: string): Promise<string[]> {
  const result = await execa('git', ['worktree', 'list', '--porcelain'], { cwd: repoRoot });
  return result.stdout
    .split('\n')
    .filter((line) => line.startsWith('worktree '))
    .map((line) => line.replace('worktree ', ''));
}

export async function pruneWorktrees(repoRoot: string): Promise<void> {
  await execa('git', ['worktree', 'prune'], { cwd: repoRoot });
}
