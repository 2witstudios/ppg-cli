import fs from 'node:fs/promises';
import YAML from 'yaml';
import type { Config, AgentConfig } from '../types/config.js';
import { configPath } from '../lib/paths.js';

const DEFAULT_CONFIG: Config = {
  sessionName: 'pogu',
  defaultAgent: 'claude',
  agents: {
    claude: {
      name: 'claude',
      command: 'claude --dangerously-skip-permissions',
      interactive: true,
      resultInstructions: [
        'When you have completed the task:',
        '',
        '1. Stage and commit all your changes with a descriptive commit message',
        '2. Push your branch: git push -u origin {{BRANCH}}',
        '3. Create a pull request: gh pr create --head {{BRANCH}} --base main --fill',
        '4. Write your results to {{RESULT_FILE}} in this format:',
        '',
        '# Result: {{AGENT_ID}}',
        '',
        '## PR',
        '<the PR URL from step 3>',
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
  const mergedAgents: Record<string, AgentConfig> = { ...defaults.agents };
  if (overrides.agents) {
    for (const [key, override] of Object.entries(overrides.agents)) {
      if (mergedAgents[key]) {
        mergedAgents[key] = { ...mergedAgents[key], ...override };
      } else {
        mergedAgents[key] = override;
      }
    }
  }
  return {
    ...defaults,
    ...overrides,
    agents: mergedAgents,
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
