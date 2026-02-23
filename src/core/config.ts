import fs from 'node:fs/promises';
import YAML from 'yaml';
import type { Config, AgentConfig } from '../types/config.js';
import { configPath } from '../lib/paths.js';

const DEFAULT_CONFIG: Config = {
  sessionName: 'ppg',
  defaultAgent: 'claude',
  agents: {
    claude: {
      name: 'claude',
      command: 'claude --dangerously-skip-permissions',
      interactive: true,
      resultInstructions: [
        'When you have completed the task, write a summary of what you did and any important notes',
        'to the result file at: {{RESULT_FILE}}',
        'Use this exact format:',
        '',
        '# Result: {{AGENT_ID}}',
        '',
        '## Summary',
        '<what you accomplished>',
        '',
        '## Changes',
        '<list of files changed>',
        '',
        '## Notes',
        '<any important observations>',
      ].join('\n'),
    },
  },
  worktreeBase: '.worktrees',
  templateDir: '.pg/templates',
  resultDir: '.pg/results',
  logDir: '.pg/logs',
  envFiles: ['.env', '.env.local'],
  symlinkNodeModules: true,
};

export async function loadConfig(projectRoot: string): Promise<Config> {
  const cfgPath = configPath(projectRoot);
  try {
    const raw = await fs.readFile(cfgPath, 'utf-8');
    const parsed = YAML.parse(raw) as Partial<Config>;
    return mergeConfig(DEFAULT_CONFIG, parsed);
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
      return DEFAULT_CONFIG;
    }
    throw err;
  }
}

function mergeConfig(defaults: Config, overrides: Partial<Config>): Config {
  return {
    ...defaults,
    ...overrides,
    agents: {
      ...defaults.agents,
      ...(overrides.agents ?? {}),
    },
  };
}

export async function writeDefaultConfig(projectRoot: string): Promise<void> {
  const cfgPath = configPath(projectRoot);
  const content = YAML.stringify(DEFAULT_CONFIG, { indent: 2 });
  await fs.writeFile(cfgPath, content, 'utf-8');
}

export function resolveAgentConfig(config: Config, name?: string): AgentConfig {
  const agentName = name ?? config.defaultAgent;
  const agent = config.agents[agentName];
  if (!agent) {
    throw new Error(`Unknown agent type: ${agentName}. Available: ${Object.keys(config.agents).join(', ')}`);
  }
  return agent;
}
