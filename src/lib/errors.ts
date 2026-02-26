export class PoguError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly exitCode: number = 1,
  ) {
    super(message);
    this.name = 'PoguError';
  }
}

export class TmuxNotFoundError extends PoguError {
  constructor() {
    super(
      'tmux is not installed or not in PATH. Install it with: brew install tmux',
      'TMUX_NOT_FOUND',
    );
    this.name = 'TmuxNotFoundError';
  }
}

export class NotGitRepoError extends PoguError {
  constructor(dir: string) {
    super(
      `Not a git repository: ${dir}`,
      'NOT_GIT_REPO',
    );
    this.name = 'NotGitRepoError';
  }
}

export class NotInitializedError extends PoguError {
  constructor(dir: string) {
    super(
      `Point Guard not initialized in ${dir}. Run 'pogu init' first.`,
      'NOT_INITIALIZED',
    );
    this.name = 'NotInitializedError';
  }
}

export class ManifestLockError extends PoguError {
  constructor() {
    super(
      'Could not acquire manifest lock. Another pogu process may be running.',
      'MANIFEST_LOCK',
    );
    this.name = 'ManifestLockError';
  }
}

export class WorktreeNotFoundError extends PoguError {
  constructor(id: string) {
    super(
      `Worktree not found: ${id}`,
      'WORKTREE_NOT_FOUND',
    );
    this.name = 'WorktreeNotFoundError';
  }
}

export class AgentNotFoundError extends PoguError {
  constructor(id: string) {
    super(
      `Agent not found: ${id}`,
      'AGENT_NOT_FOUND',
    );
    this.name = 'AgentNotFoundError';
  }
}

export class MergeFailedError extends PoguError {
  constructor(message: string) {
    super(message, 'MERGE_FAILED');
    this.name = 'MergeFailedError';
  }
}

export class GhNotFoundError extends PoguError {
  constructor() {
    super(
      'GitHub CLI (gh) is not installed or not in PATH. Install it with: brew install gh',
      'GH_NOT_FOUND',
    );
    this.name = 'GhNotFoundError';
  }
}

export class UnmergedWorkError extends PoguError {
  constructor(names: string[]) {
    const list = names.map((n) => `  ${n}`).join('\n');
    super(
      `${names.length} worktree(s) have completed work that hasn't been merged or PR'd:\n${list}\n\nUse --force to reset anyway, or create PRs first with: pogu pr <worktree-id>`,
      'UNMERGED_WORK',
    );
    this.name = 'UnmergedWorkError';
  }
}
