import os from 'node:os';
import path from 'node:path';

const PPG_DIR = '.ppg';

export function globalPpgDir(): string {
  return path.join(os.homedir(), PPG_DIR);
}

export function globalPromptsDir(): string {
  return path.join(globalPpgDir(), 'prompts');
}

export function globalTemplatesDir(): string {
  return path.join(globalPpgDir(), 'templates');
}

export function globalSwarmsDir(): string {
  return path.join(globalPpgDir(), 'swarms');
}

export function ppgDir(projectRoot: string): string {
  return path.join(projectRoot, PPG_DIR);
}

export function manifestPath(projectRoot: string): string {
  return path.join(ppgDir(projectRoot), 'manifest.json');
}

export function configPath(projectRoot: string): string {
  return path.join(ppgDir(projectRoot), 'config.yaml');
}

export function resultsDir(projectRoot: string): string {
  return path.join(ppgDir(projectRoot), 'results');
}

export function resultFile(projectRoot: string, agentId: string): string {
  return path.join(resultsDir(projectRoot), `${agentId}.md`);
}

export function templatesDir(projectRoot: string): string {
  return path.join(ppgDir(projectRoot), 'templates');
}

export function logsDir(projectRoot: string): string {
  return path.join(ppgDir(projectRoot), 'logs');
}

export function promptsDir(projectRoot: string): string {
  return path.join(ppgDir(projectRoot), 'prompts');
}

export function swarmsDir(projectRoot: string): string {
  return path.join(ppgDir(projectRoot), 'swarms');
}

export function promptFile(projectRoot: string, agentId: string): string {
  return path.join(promptsDir(projectRoot), `${agentId}.md`);
}

export function agentPromptsDir(projectRoot: string): string {
  return path.join(ppgDir(projectRoot), 'agent-prompts');
}

export function agentPromptFile(projectRoot: string, agentId: string): string {
  return path.join(agentPromptsDir(projectRoot), `${agentId}.md`);
}

export function schedulesPath(projectRoot: string): string {
  return path.join(ppgDir(projectRoot), 'schedules.yaml');
}

export function cronLogPath(projectRoot: string): string {
  return path.join(logsDir(projectRoot), 'cron.log');
}

export function cronPidPath(projectRoot: string): string {
  return path.join(ppgDir(projectRoot), 'cron.pid');
}

export function worktreeBaseDir(projectRoot: string): string {
  return path.join(projectRoot, '.worktrees');
}

export function worktreePath(projectRoot: string, id: string): string {
  return path.join(worktreeBaseDir(projectRoot), id);
}

export function serveDir(projectRoot: string): string {
  return path.join(ppgDir(projectRoot), 'serve');
}

export function authPath(projectRoot: string): string {
  return path.join(serveDir(projectRoot), 'auth.json');
}
