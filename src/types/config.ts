export interface AgentConfig {
  name: string;
  command: string;
  promptFlag?: string;
  promptFileFlag?: string;
  interactive: boolean;
}

export interface Config {
  sessionName: string;
  defaultAgent: string;
  agents: Record<string, AgentConfig>;
  envFiles: string[];
  symlinkNodeModules: boolean;
}
