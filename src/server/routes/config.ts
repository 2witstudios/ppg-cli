import fs from 'node:fs/promises';
import path from 'node:path';
import type { FastifyInstance } from 'fastify';
import { loadConfig } from '../../core/config.js';
import { listTemplatesWithSource } from '../../core/template.js';
import {
  templatesDir,
  globalTemplatesDir,
  promptsDir,
  globalPromptsDir,
} from '../../lib/paths.js';

export interface ConfigRouteOptions {
  projectRoot: string;
}

interface TemplateResponse {
  name: string;
  description: string;
  variables: string[];
  source: 'local' | 'global';
}

interface PromptResponse {
  name: string;
  description: string;
  variables: string[];
  source: 'local' | 'global';
}

async function listPromptEntries(
  projectRoot: string,
): Promise<Array<{ name: string; source: 'local' | 'global' }>> {
  const localDir = promptsDir(projectRoot);
  const globalDir = globalPromptsDir();

  let localFiles: string[] = [];
  try {
    localFiles = (await fs.readdir(localDir)).filter((f) => f.endsWith('.md')).sort();
  } catch {
    // directory doesn't exist
  }

  let globalFiles: string[] = [];
  try {
    globalFiles = (await fs.readdir(globalDir)).filter((f) => f.endsWith('.md')).sort();
  } catch {
    // directory doesn't exist
  }

  const seen = new Set<string>();
  const result: Array<{ name: string; source: 'local' | 'global' }> = [];

  for (const file of localFiles) {
    const name = file.replace(/\.md$/, '');
    seen.add(name);
    result.push({ name, source: 'local' });
  }

  for (const file of globalFiles) {
    const name = file.replace(/\.md$/, '');
    if (!seen.has(name)) {
      result.push({ name, source: 'global' });
    }
  }

  return result;
}

async function enrichWithMetadata(
  name: string,
  source: 'local' | 'global',
  localDir: string,
  globalDir: string,
): Promise<{ name: string; description: string; variables: string[]; source: 'local' | 'global' }> {
  const dir = source === 'local' ? localDir : globalDir;
  const filePath = path.join(dir, `${name}.md`);
  const content = await fs.readFile(filePath, 'utf-8');
  const firstLine = content.split('\n').find((l) => l.trim().length > 0) ?? '';
  const description = firstLine.replace(/^#+\s*/, '').trim();
  const vars = [...content.matchAll(/\{\{(\w+)\}\}/g)].map((m) => m[1]);
  const uniqueVars = [...new Set(vars)];

  return { name, description, variables: uniqueVars, source };
}

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
    const templates: TemplateResponse[] = await Promise.all(
      entries.map(({ name, source }) =>
        enrichWithMetadata(
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
    const entries = await listPromptEntries(projectRoot);
    const prompts: PromptResponse[] = await Promise.all(
      entries.map(({ name, source }) =>
        enrichWithMetadata(
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
