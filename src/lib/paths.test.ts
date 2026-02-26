import { describe, test, expect } from 'vitest';
import path from 'node:path';
import {
  poguDir,
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
  test('poguDir', () => {
    expect(poguDir(ROOT)).toBe(path.join(ROOT, '.pogu'));
  });

  test('manifestPath', () => {
    expect(manifestPath(ROOT)).toBe(path.join(ROOT, '.pogu', 'manifest.json'));
  });

  test('configPath', () => {
    expect(configPath(ROOT)).toBe(path.join(ROOT, '.pogu', 'config.yaml'));
  });

  test('resultsDir', () => {
    expect(resultsDir(ROOT)).toBe(path.join(ROOT, '.pogu', 'results'));
  });

  test('resultFile', () => {
    expect(resultFile(ROOT, 'ag-abc12345')).toBe(
      path.join(ROOT, '.pogu', 'results', 'ag-abc12345.md'),
    );
  });

  test('templatesDir', () => {
    expect(templatesDir(ROOT)).toBe(path.join(ROOT, '.pogu', 'templates'));
  });

  test('logsDir', () => {
    expect(logsDir(ROOT)).toBe(path.join(ROOT, '.pogu', 'logs'));
  });

  test('promptsDir', () => {
    expect(promptsDir(ROOT)).toBe(path.join(ROOT, '.pogu', 'prompts'));
  });

  test('swarmsDir', () => {
    expect(swarmsDir(ROOT)).toBe(path.join(ROOT, '.pogu', 'swarms'));
  });

  test('promptFile', () => {
    expect(promptFile(ROOT, 'ag-abc12345')).toBe(
      path.join(ROOT, '.pogu', 'prompts', 'ag-abc12345.md'),
    );
  });

  test('agentPromptsDir', () => {
    expect(agentPromptsDir(ROOT)).toBe(path.join(ROOT, '.pogu', 'agent-prompts'));
  });

  test('agentPromptFile', () => {
    expect(agentPromptFile(ROOT, 'ag-abc12345')).toBe(
      path.join(ROOT, '.pogu', 'agent-prompts', 'ag-abc12345.md'),
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
