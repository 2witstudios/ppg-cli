import fs from 'node:fs/promises';
import path from 'node:path';
import { getRepoRoot } from '../core/worktree.js';
import { promptsDir } from '../lib/paths.js';
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

export async function promptCommand(promptName: string, options: PromptCommandOptions): Promise<void> {
  const projectRoot = await getRepoRoot();
  const promptFile = path.join(promptsDir(projectRoot), `${promptName}.md`);

  try {
    await fs.access(promptFile);
  } catch {
    throw new PpgError(`Prompt not found: ${promptName} (expected ${promptFile})`, 'INVALID_ARGS');
  }

  const spawnOpts: SpawnOptions = {
    name: options.name ?? promptName,
    agent: options.agent,
    promptFile: promptFile,
    var: options.var,
    base: options.base,
    count: options.count,
    split: options.split,
    open: options.open,
    json: options.json,
  };

  await spawnCommand(spawnOpts);
}
