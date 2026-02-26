import { describe, test, expect, vi, beforeEach } from 'vitest';
import { loadConfig, resolveAgentConfig } from './config.js';
import type { Config } from '../types/config.js';

// Mock node:fs/promises
vi.mock('node:fs/promises', () => ({
  default: {
    readFile: vi.fn(),
    writeFile: vi.fn(),
  },
}));

// We need to import the mocked module to control its behavior
import fs from 'node:fs/promises';

const mockedReadFile = vi.mocked(fs.readFile);

beforeEach(() => {
  vi.clearAllMocks();
});

describe('loadConfig', () => {
  test('given ENOENT, should return default config', async () => {
    const err = new Error('ENOENT') as NodeJS.ErrnoException;
    err.code = 'ENOENT';
    mockedReadFile.mockRejectedValue(err);

    const config = await loadConfig('/tmp/project');

    expect(config.sessionName).toBe('ppg');
    expect(config.defaultAgent).toBe('claude');
    expect(config.agents.claude).toBeDefined();
    expect(config.agents.claude.command).toBe('claude --dangerously-skip-permissions');
    expect(config.symlinkNodeModules).toBe(true);
  });

  test('given valid YAML, should merge with defaults', async () => {
    const yaml = `
sessionName: custom-session
defaultAgent: claude
`;
    mockedReadFile.mockResolvedValue(yaml);

    const config = await loadConfig('/tmp/project');

    expect(config.sessionName).toBe('custom-session');
    // Defaults should still be present
    expect(config.agents.claude).toBeDefined();
    expect(config.symlinkNodeModules).toBe(true);
  });

  test('given override agents, should merge with default agents', async () => {
    const yaml = `
agents:
  custom:
    name: custom
    command: "echo hello"
    interactive: false
`;
    mockedReadFile.mockResolvedValue(yaml);

    const config = await loadConfig('/tmp/project');

    // Custom agent present
    expect(config.agents.custom).toBeDefined();
    expect(config.agents.custom.command).toBe('echo hello');
    // Default claude agent still present
    expect(config.agents.claude).toBeDefined();
  });

  test('given non-ENOENT error, should throw', async () => {
    const err = new Error('EACCES') as NodeJS.ErrnoException;
    err.code = 'EACCES';
    mockedReadFile.mockRejectedValue(err);

    await expect(loadConfig('/tmp/project')).rejects.toThrow('EACCES');
  });
});

describe('resolveAgentConfig', () => {
  const config: Config = {
    sessionName: 'ppg',
    defaultAgent: 'claude',
    agents: {
      claude: {
        name: 'claude',
        command: 'claude --dangerously-skip-permissions',
        interactive: true,
      },
      codex: {
        name: 'codex',
        command: 'codex',
        interactive: false,
      },
    },
    envFiles: ['.env'],
    symlinkNodeModules: true,
  };

  test('given valid name, should return that agent config', () => {
    const agent = resolveAgentConfig(config, 'codex');
    expect(agent.name).toBe('codex');
    expect(agent.command).toBe('codex');
  });

  test('given no name, should return default agent', () => {
    const agent = resolveAgentConfig(config);
    expect(agent.name).toBe('claude');
  });

  test('given unknown name, should throw with available agents', () => {
    expect(() => resolveAgentConfig(config, 'nonexistent')).toThrow(
      /Unknown agent type: nonexistent/,
    );
    expect(() => resolveAgentConfig(config, 'nonexistent')).toThrow(
      /Available: claude, codex/,
    );
  });
});
