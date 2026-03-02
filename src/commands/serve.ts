import { getRepoRoot } from '../core/worktree.js';
import { requireManifest } from '../core/manifest.js';
import { startServer } from '../server/index.js';

export interface ServeCommandOptions {
  port: number;
  host: string;
  token?: string;
  json?: boolean;
}

export async function serveCommand(options: ServeCommandOptions): Promise<void> {
  const projectRoot = await getRepoRoot();
  await requireManifest(projectRoot);

  await startServer({
    projectRoot,
    port: options.port,
    host: options.host,
    token: options.token,
    json: options.json,
  });
}
