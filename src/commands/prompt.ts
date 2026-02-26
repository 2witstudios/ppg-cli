import fs from 'node:fs/promises';
import path from 'node:path';
import { getRepoRoot } from '../core/worktree.js';
import { promptsDir, globalPromptsDir } from '../lib/paths.js';
import { PpgError } from '../lib/errors.js';
import { spawnCommand, type SpawnOptions } from './spawn.js';

export interface PromptCommandOptions {
  name?: string;
  agent?: string;
  var?: string[];
  base?: string;
  count?: number;
  split?: boolean;
  open?: boolean;
  json?: boolean;
}

async function resolvePromptFile(projectRoot: string, promptName: string): Promise<string> {
  // Try project-local first
  const localPath = path.join(promptsDir(projectRoot), `${promptName}.md`);
  try {
    await fs.access(localPath);
    return localPath;
  } catch {
    // Fall back to global
    const globalPath = path.join(globalPromptsDir(), `${promptName}.md`);
    try {
      await fs.access(globalPath);
      return globalPath;
    } catch {
      throw new PpgError(
        `Prompt not found: ${promptName} (checked .ppg/prompts/ and ~/.ppg/prompts/)`,
        'INVALID_ARGS',
      );
    }
  }
}

export async function promptCommand(promptName: string, options: PromptCommandOptions): Promise<void> {
  const projectRoot = await getRepoRoot();
  const promptFilePath = await resolvePromptFile(projectRoot, promptName);

  const spawnOpts: SpawnOptions = {
    name: options.name ?? promptName,
    agent: options.agent,
    promptFile: promptFilePath,
    var: options.var,
    base: options.base,
    count: options.count,
    split: options.split,
    open: options.open,
    json: options.json,
  };

  await spawnCommand(spawnOpts);
}
