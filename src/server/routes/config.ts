import type { FastifyInstance } from 'fastify';
import { loadConfig } from '../../core/config.js';
import { listTemplatesWithSource } from '../../core/template.js';
import { listPromptsWithSource, enrichEntryMetadata } from '../../core/prompt.js';
import {
  templatesDir,
  globalTemplatesDir,
  promptsDir,
  globalPromptsDir,
} from '../../lib/paths.js';

export interface ConfigRouteOptions {
  projectRoot: string;
}

// Auth note: these routes expect the parent server to register an onRequest
// auth hook before this plugin (e.g. Bearer token via createAuthHook).

export async function configRoutes(
  app: FastifyInstance,
  opts: ConfigRouteOptions,
): Promise<void> {
  const { projectRoot } = opts;

  // GET /api/config — agent configuration from config.yaml
  app.get('/api/config', async () => {
    const config = await loadConfig(projectRoot);
    return {
      sessionName: config.sessionName,
      defaultAgent: config.defaultAgent,
      agents: Object.values(config.agents),
      envFiles: config.envFiles,
      symlinkNodeModules: config.symlinkNodeModules,
    };
  });

  // GET /api/templates — templates with source tracking
  app.get('/api/templates', async () => {
    const entries = await listTemplatesWithSource(projectRoot);
    const templates = await Promise.all(
      entries.map(({ name, source }) =>
        enrichEntryMetadata(
          name,
          source,
          templatesDir(projectRoot),
          globalTemplatesDir(),
        ),
      ),
    );
    return { templates };
  });

  // GET /api/prompts — prompts with deduplication across local/global
  app.get('/api/prompts', async () => {
    const entries = await listPromptsWithSource(projectRoot);
    const prompts = await Promise.all(
      entries.map(({ name, source }) =>
        enrichEntryMetadata(
          name,
          source,
          promptsDir(projectRoot),
          globalPromptsDir(),
        ),
      ),
    );
    return { prompts };
  });
}
