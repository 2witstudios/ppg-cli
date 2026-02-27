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
  serveDir,
  tlsDir,
  tlsCaKeyPath,
  tlsCaCertPath,
  tlsServerKeyPath,
  tlsServerCertPath,
  worktreeBaseDir,
  worktreePath,
  globalPpgDir,
  globalPromptsDir,
  globalTemplatesDir,
  globalSwarmsDir,
  serveStatePath,
  servePidPath,
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

  test('serveDir', () => {
    expect(serveDir(ROOT)).toBe(path.join(ROOT, '.ppg', 'serve'));
  });

  test('tlsDir', () => {
    expect(tlsDir(ROOT)).toBe(path.join(ROOT, '.ppg', 'serve', 'tls'));
  });

  test('tlsCaKeyPath', () => {
    expect(tlsCaKeyPath(ROOT)).toBe(path.join(ROOT, '.ppg', 'serve', 'tls', 'ca-key.pem'));
  });

  test('tlsCaCertPath', () => {
    expect(tlsCaCertPath(ROOT)).toBe(path.join(ROOT, '.ppg', 'serve', 'tls', 'ca-cert.pem'));
  });

  test('tlsServerKeyPath', () => {
    expect(tlsServerKeyPath(ROOT)).toBe(path.join(ROOT, '.ppg', 'serve', 'tls', 'server-key.pem'));
  });

  test('tlsServerCertPath', () => {
    expect(tlsServerCertPath(ROOT)).toBe(path.join(ROOT, '.ppg', 'serve', 'tls', 'server-cert.pem'));
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

  test('serveStatePath', () => {
    expect(serveStatePath(ROOT)).toBe(path.join(ROOT, '.ppg', 'serve.json'));
  });

  test('servePidPath', () => {
    expect(servePidPath(ROOT)).toBe(path.join(ROOT, '.ppg', 'serve.pid'));
  });
});
