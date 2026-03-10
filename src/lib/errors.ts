export class PpgError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly exitCode: number = 1,
  ) {
    super(message);
    this.name = 'PpgError';
  }
}

export class TmuxNotFoundError extends PpgError {
  constructor() {
    super(
      'tmux is not installed or not in PATH. Install it with: brew install tmux',
      'TMUX_NOT_FOUND',
    );
    this.name = 'TmuxNotFoundError';
  }
}

export class NotGitRepoError extends PpgError {
  constructor(dir: string) {
    super(
      `Not a git repository: ${dir}`,
      'NOT_GIT_REPO',
    );
    this.name = 'NotGitRepoError';
  }
}

export class NotInitializedError extends PpgError {
  constructor(dir: string) {
    super(
      `Point Guard not initialized in ${dir}. Run 'ppg init' first.`,
      'NOT_INITIALIZED',
    );
    this.name = 'NotInitializedError';
  }
}

export class ManifestLockError extends PpgError {
  constructor() {
    super(
      'Could not acquire manifest lock. Another ppg process may be running.',
      'MANIFEST_LOCK',
    );
    this.name = 'ManifestLockError';
  }
}

export class WorktreeNotFoundError extends PpgError {
  constructor(id: string) {
    super(
      `Worktree not found: ${id}`,
      'WORKTREE_NOT_FOUND',
    );
    this.name = 'WorktreeNotFoundError';
  }
}

export class AgentNotFoundError extends PpgError {
  constructor(id: string) {
    super(
      `Agent not found: ${id}`,
      'AGENT_NOT_FOUND',
    );
    this.name = 'AgentNotFoundError';
  }
}

export class MergeFailedError extends PpgError {
  constructor(message: string) {
    super(message, 'MERGE_FAILED');
    this.name = 'MergeFailedError';
  }
}

export class GhNotFoundError extends PpgError {
  constructor() {
    super(
      'GitHub CLI (gh) is not installed or not in PATH. Install it with: brew install gh',
      'GH_NOT_FOUND',
    );
    this.name = 'GhNotFoundError';
  }
}

export class DuplicateTokenError extends PpgError {
  constructor(label: string) {
    super(
      `Token with label "${label}" already exists`,
      'DUPLICATE_TOKEN',
    );
    this.name = 'DuplicateTokenError';
  }
}

export class AuthCorruptError extends PpgError {
  constructor(filePath: string) {
    super(
      `Auth data is corrupt or unreadable: ${filePath}`,
      'AUTH_CORRUPT',
    );
    this.name = 'AuthCorruptError';
  }
}

export class UnmergedWorkError extends PpgError {
  constructor(names: string[]) {
    const list = names.map((n) => `  ${n}`).join('\n');
    super(
      `${names.length} worktree(s) have unmerged work that hasn't been PR'd:\n${list}\n\nUse --force to reset anyway, or create PRs first with: ppg pr <worktree-id>`,
      'UNMERGED_WORK',
    );
    this.name = 'UnmergedWorkError';
  }
}
