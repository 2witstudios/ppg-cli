export class PgError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly exitCode: number = 1,
  ) {
    super(message);
    this.name = 'PgError';
  }
}

export class TmuxNotFoundError extends PgError {
  constructor() {
    super(
      'tmux is not installed or not in PATH. Install it with: brew install tmux',
      'TMUX_NOT_FOUND',
    );
    this.name = 'TmuxNotFoundError';
  }
}

export class NotGitRepoError extends PgError {
  constructor(dir: string) {
    super(
      `Not a git repository: ${dir}`,
      'NOT_GIT_REPO',
    );
    this.name = 'NotGitRepoError';
  }
}

export class NotInitializedError extends PgError {
  constructor(dir: string) {
    super(
      `Point Guard not initialized in ${dir}. Run 'ppg init' first.`,
      'NOT_INITIALIZED',
    );
    this.name = 'NotInitializedError';
  }
}

export class ManifestLockError extends PgError {
  constructor() {
    super(
      'Could not acquire manifest lock. Another ppg process may be running.',
      'MANIFEST_LOCK',
    );
    this.name = 'ManifestLockError';
  }
}

export class WorktreeNotFoundError extends PgError {
  constructor(id: string) {
    super(
      `Worktree not found: ${id}`,
      'WORKTREE_NOT_FOUND',
    );
    this.name = 'WorktreeNotFoundError';
  }
}

export class AgentNotFoundError extends PgError {
  constructor(id: string) {
    super(
      `Agent not found: ${id}`,
      'AGENT_NOT_FOUND',
    );
    this.name = 'AgentNotFoundError';
  }
}

export class MergeFailedError extends PgError {
  constructor(message: string) {
    super(message, 'MERGE_FAILED');
    this.name = 'MergeFailedError';
  }
}
