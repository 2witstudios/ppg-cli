export type AgentStatus =
  | 'spawning'
  | 'running'
  | 'waiting'
  | 'completed'
  | 'failed'
  | 'killed'
  | 'lost';

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
  resultFile: string;
  startedAt: string;
  completedAt?: string;
  exitCode?: number;
  error?: string;
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
  agents: Record<string, AgentEntry>;
  createdAt: string;
  mergedAt?: string;
}

export interface Manifest {
  version: 1;
  projectRoot: string;
  sessionName: string;
  worktrees: Record<string, WorktreeEntry>;
  createdAt: string;
  updatedAt: string;
}
