export type AgentStatus =
  | 'running'
  | 'idle'
  | 'exited'
  | 'gone';

export type WorktreeStatus =
  | 'active'
  | 'merging'
  | 'merged'
  | 'failed'
  | 'cleaned';

export interface AgentEntry {
  id: string;
  name: string;
  agentType: string;
  status: AgentStatus;
  tmuxTarget: string;
  prompt: string;
  startedAt: string;
  exitCode?: number;
  sessionId?: string;
}

export interface WorktreeEntry {
  id: string;
  name: string;
  path: string;
  branch: string;
  baseBranch: string;
  status: WorktreeStatus;
  tmuxWindow: string;
  prUrl?: string;
  agents: Record<string, AgentEntry>;
  createdAt: string;
  mergedAt?: string;
}

export interface Manifest {
  version: 1;
  projectRoot: string;
  sessionName: string;
  agents: Record<string, AgentEntry>;
  worktrees: Record<string, WorktreeEntry>;
  createdAt: string;
  updatedAt: string;
}
