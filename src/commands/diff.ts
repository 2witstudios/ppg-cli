import { execa } from 'execa';
import { readManifest, getWorktree } from '../core/manifest.js';
import { getRepoRoot } from '../core/worktree.js';
import { NotInitializedError, WorktreeNotFoundError } from '../lib/errors.js';
import { output } from '../lib/output.js';

export interface DiffOptions {
  stat?: boolean;
  nameOnly?: boolean;
  json?: boolean;
}

export async function diffCommand(worktreeRef: string, options: DiffOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  let manifest;
  try {
    manifest = await readManifest(projectRoot);
  } catch {
    throw new NotInitializedError(projectRoot);
  }

  const wt = getWorktree(manifest, worktreeRef)
    ?? Object.values(manifest.worktrees).find((w) => w.name === worktreeRef);

  if (!wt) throw new WorktreeNotFoundError(worktreeRef);

  const diffRange = `${wt.baseBranch}...${wt.branch}`;

  if (options.json) {
    // Machine-readable: numstat for file-level changes
    const result = await execa('git', ['diff', '--numstat', diffRange], { cwd: projectRoot });
    const files = result.stdout.trim().split('\n').filter(Boolean).map((line) => {
      const [added, removed, file] = line.split('\t');
      return {
        file,
        added: added === '-' ? 0 : parseInt(added, 10),
        removed: removed === '-' ? 0 : parseInt(removed, 10),
      };
    });
    output({
      worktreeId: wt.id,
      branch: wt.branch,
      baseBranch: wt.baseBranch,
      files,
    }, true);
  } else if (options.stat) {
    const result = await execa('git', ['diff', '--stat', diffRange], { cwd: projectRoot });
    console.log(result.stdout);
  } else if (options.nameOnly) {
    const result = await execa('git', ['diff', '--name-only', diffRange], { cwd: projectRoot });
    console.log(result.stdout);
  } else {
    const result = await execa('git', ['diff', diffRange], { cwd: projectRoot });
    console.log(result.stdout);
  }
}
