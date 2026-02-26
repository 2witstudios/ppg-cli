import { describe, test, expect } from 'vitest';
import os from 'node:os';
import path from 'node:path';
import {
  ppgDir,
  manifestPath,
  configPath,
  resultsDir,
  resultFile,
  templatesDir,
  logsDir,
  promptsDir,
  swarmsDir,
  promptFile,
  agentPromptsDir,
  agentPromptFile,
  worktreeBaseDir,
  worktreePath,
  globalPpgDir,
  globalPromptsDir,
  globalTemplatesDir,
  globalSwarmsDir,
} from './paths.js';

const ROOT = '/tmp/project';

describe('paths', () => {
  test('ppgDir', () => {
    expect(ppgDir(ROOT)).toBe(path.join(ROOT, '.ppg'));
  });

  test('manifestPath', () => {
    expect(manifestPath(ROOT)).toBe(path.join(ROOT, '.ppg', 'manifest.json'));
  });

  test('configPath', () => {
    expect(configPath(ROOT)).toBe(path.join(ROOT, '.ppg', 'config.yaml'));
  });

  test('resultsDir', () => {
    expect(resultsDir(ROOT)).toBe(path.join(ROOT, '.ppg', 'results'));
  });

  test('resultFile', () => {
    expect(resultFile(ROOT, 'ag-abc12345')).toBe(
      path.join(ROOT, '.ppg', 'results', 'ag-abc12345.md'),
    );
  });

  test('templatesDir', () => {
    expect(templatesDir(ROOT)).toBe(path.join(ROOT, '.ppg', 'templates'));
  });

  test('logsDir', () => {
    expect(logsDir(ROOT)).toBe(path.join(ROOT, '.ppg', 'logs'));
  });

  test('promptsDir', () => {
    expect(promptsDir(ROOT)).toBe(path.join(ROOT, '.ppg', 'prompts'));
  });

  test('swarmsDir', () => {
    expect(swarmsDir(ROOT)).toBe(path.join(ROOT, '.ppg', 'swarms'));
  });

  test('promptFile', () => {
    expect(promptFile(ROOT, 'ag-abc12345')).toBe(
      path.join(ROOT, '.ppg', 'prompts', 'ag-abc12345.md'),
    );
  });

  test('agentPromptsDir', () => {
    expect(agentPromptsDir(ROOT)).toBe(path.join(ROOT, '.ppg', 'agent-prompts'));
  });

  test('agentPromptFile', () => {
    expect(agentPromptFile(ROOT, 'ag-abc12345')).toBe(
      path.join(ROOT, '.ppg', 'agent-prompts', 'ag-abc12345.md'),
    );
  });

  test('worktreeBaseDir', () => {
    expect(worktreeBaseDir(ROOT)).toBe(path.join(ROOT, '.worktrees'));
  });

  test('worktreePath', () => {
    expect(worktreePath(ROOT, 'wt-abc123')).toBe(
      path.join(ROOT, '.worktrees', 'wt-abc123'),
    );
  });

  test('globalPpgDir', () => {
    expect(globalPpgDir()).toBe(path.join(os.homedir(), '.ppg'));
  });

  test('globalPromptsDir', () => {
    expect(globalPromptsDir()).toBe(path.join(os.homedir(), '.ppg', 'prompts'));
  });

  test('globalTemplatesDir', () => {
    expect(globalTemplatesDir()).toBe(path.join(os.homedir(), '.ppg', 'templates'));
  });

  test('globalSwarmsDir', () => {
    expect(globalSwarmsDir()).toBe(path.join(os.homedir(), '.ppg', 'swarms'));
  });
});
