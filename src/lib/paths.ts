import path from 'node:path';

const PG_DIR = '.pg';

export function pgDir(projectRoot: string): string {
  return path.join(projectRoot, PG_DIR);
}

export function manifestPath(projectRoot: string): string {
  return path.join(pgDir(projectRoot), 'manifest.json');
}

export function configPath(projectRoot: string): string {
  return path.join(pgDir(projectRoot), 'config.yaml');
}

export function resultsDir(projectRoot: string): string {
  return path.join(pgDir(projectRoot), 'results');
}

export function resultFile(projectRoot: string, agentId: string): string {
  return path.join(resultsDir(projectRoot), `${agentId}.md`);
}

export function templatesDir(projectRoot: string): string {
  return path.join(pgDir(projectRoot), 'templates');
}

export function logsDir(projectRoot: string): string {
  return path.join(pgDir(projectRoot), 'logs');
}

export function promptsDir(projectRoot: string): string {
  return path.join(pgDir(projectRoot), 'prompts');
}

export function swarmsDir(projectRoot: string): string {
  return path.join(pgDir(projectRoot), 'swarms');
}

export function promptFile(projectRoot: string, agentId: string): string {
  return path.join(promptsDir(projectRoot), `${agentId}.md`);
}

export function agentPromptsDir(projectRoot: string): string {
  return path.join(pgDir(projectRoot), 'agent-prompts');
}

export function agentPromptFile(projectRoot: string, agentId: string): string {
  return path.join(agentPromptsDir(projectRoot), `${agentId}.md`);
}

export function worktreeBaseDir(projectRoot: string): string {
  return path.join(projectRoot, '.worktrees');
}

export function worktreePath(projectRoot: string, id: string): string {
  return path.join(worktreeBaseDir(projectRoot), id);
}
