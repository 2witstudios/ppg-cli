export interface AgentConfig {
  name: string;
  command: string;
  promptFlag?: string;
  promptFileFlag?: string;
  interactive: boolean;
  resultInstructions?: string;
}

export interface Config {
  sessionName: string;
  defaultAgent: string;
  agents: Record<string, AgentConfig>;
  worktreeBase: string;
  templateDir: string;
  resultDir: string;
  logDir: string;
  envFiles: string[];
  symlinkNodeModules: boolean;
}
