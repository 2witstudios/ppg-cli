import { describe, test, expect } from 'vitest';
import path from 'node:path';
import {
  pgDir,
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
} from './paths.js';

const ROOT = '/tmp/project';

describe('paths', () => {
  test('pgDir', () => {
    expect(pgDir(ROOT)).toBe(path.join(ROOT, '.pg'));
  });

  test('manifestPath', () => {
    expect(manifestPath(ROOT)).toBe(path.join(ROOT, '.pg', 'manifest.json'));
  });

  test('configPath', () => {
    expect(configPath(ROOT)).toBe(path.join(ROOT, '.pg', 'config.yaml'));
  });

  test('resultsDir', () => {
    expect(resultsDir(ROOT)).toBe(path.join(ROOT, '.pg', 'results'));
  });

  test('resultFile', () => {
    expect(resultFile(ROOT, 'ag-abc12345')).toBe(
      path.join(ROOT, '.pg', 'results', 'ag-abc12345.md'),
    );
  });

  test('templatesDir', () => {
    expect(templatesDir(ROOT)).toBe(path.join(ROOT, '.pg', 'templates'));
  });

  test('logsDir', () => {
    expect(logsDir(ROOT)).toBe(path.join(ROOT, '.pg', 'logs'));
  });

  test('promptsDir', () => {
    expect(promptsDir(ROOT)).toBe(path.join(ROOT, '.pg', 'prompts'));
  });

  test('swarmsDir', () => {
    expect(swarmsDir(ROOT)).toBe(path.join(ROOT, '.pg', 'swarms'));
  });

  test('promptFile', () => {
    expect(promptFile(ROOT, 'ag-abc12345')).toBe(
      path.join(ROOT, '.pg', 'prompts', 'ag-abc12345.md'),
    );
  });

  test('agentPromptsDir', () => {
    expect(agentPromptsDir(ROOT)).toBe(path.join(ROOT, '.pg', 'agent-prompts'));
  });

  test('agentPromptFile', () => {
    expect(agentPromptFile(ROOT, 'ag-abc12345')).toBe(
      path.join(ROOT, '.pg', 'agent-prompts', 'ag-abc12345.md'),
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
});
