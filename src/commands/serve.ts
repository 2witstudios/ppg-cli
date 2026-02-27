import { execa } from 'execa';
import { NotGitRepoError, NotInitializedError } from '../lib/errors.js';
import { ppgDir } from '../lib/paths.js';
import { startServer } from '../server/index.js';
import { execaEnv } from '../lib/env.js';
import fs from 'node:fs/promises';

async function resolveProjectRoot(): Promise<string> {
  const cwd = process.cwd();
  let projectRoot: string;
  try {
    const result = await execa('git', ['rev-parse', '--show-toplevel'], { ...execaEnv, cwd });
    projectRoot = result.stdout.trim();
  } catch {
    throw new NotGitRepoError(cwd);
  }
  try {
    await fs.access(ppgDir(projectRoot));
  } catch {
    throw new NotInitializedError(projectRoot);
  }
  return projectRoot;
}

export interface ServeCommandOptions {
  port?: number;
  host?: string;
  token?: string;
  daemon?: boolean;
  json?: boolean;
}

export async function serveCommand(options: ServeCommandOptions): Promise<void> {
  const projectRoot = await resolveProjectRoot();

  const port = options.port ?? 3100;
  const host = options.host ?? '127.0.0.1';

  await startServer({
    projectRoot,
    port,
    host,
    token: options.token,
    json: options.json,
  });
}
