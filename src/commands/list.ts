import fs from 'node:fs/promises';
import path from 'node:path';
import { getRepoRoot } from '../core/worktree.js';
import { listTemplates } from '../core/template.js';
import { listSwarms, loadSwarm } from '../core/swarm.js';
import { templatesDir } from '../lib/paths.js';
import { PgError } from '../lib/errors.js';
import { output, formatTable, type Column } from '../lib/output.js';

export interface ListOptions {
  json?: boolean;
}

export async function listCommand(type: string, options: ListOptions): Promise<void> {
  if (type === 'templates') {
    await listTemplatesCommand(options);
  } else if (type === 'swarms') {
    await listSwarmsCommand(options);
  } else {
    throw new PgError(`Unknown list type: ${type}. Available: templates, swarms`, 'INVALID_ARGS');
  }
}

async function listTemplatesCommand(options: ListOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  const templateNames = await listTemplates(projectRoot);

  if (templateNames.length === 0) {
    console.log('No templates found in .pg/templates/');
    return;
  }

  const templates = await Promise.all(
    templateNames.map(async (name) => {
      const filePath = path.join(templatesDir(projectRoot), `${name}.md`);
      const content = await fs.readFile(filePath, 'utf-8');
      const firstLine = content.split('\n').find((l) => l.trim().length > 0) ?? '';
      const description = firstLine.replace(/^#+\s*/, '').trim();

      // Extract template variables
      const vars = [...content.matchAll(/\{\{(\w+)\}\}/g)].map((m) => m[1]);
      const uniqueVars = [...new Set(vars)];

      return { name, description, variables: uniqueVars };
    }),
  );

  if (options.json) {
    output({ templates }, true);
    return;
  }

  const columns: Column[] = [
    { header: 'Name', key: 'name', width: 20 },
    { header: 'Description', key: 'description', width: 40 },
    {
      header: 'Variables',
      key: 'variables',
      width: 30,
      format: (v) => (v as string[]).join(', '),
    },
  ];

  console.log(formatTable(templates, columns));
}

async function listSwarmsCommand(options: ListOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  const swarmNames = await listSwarms(projectRoot);

  if (swarmNames.length === 0) {
    console.log('No swarm templates found in .pg/swarms/');
    return;
  }

  const swarms = await Promise.all(
    swarmNames.map(async (name) => {
      const swarm = await loadSwarm(projectRoot, name);
      return {
        name: swarm.name,
        description: swarm.description,
        strategy: swarm.strategy,
        agents: swarm.agents.length,
      };
    }),
  );

  if (options.json) {
    output({ swarms }, true);
    return;
  }

  const columns: Column[] = [
    { header: 'Name', key: 'name', width: 20 },
    { header: 'Description', key: 'description', width: 40 },
    { header: 'Strategy', key: 'strategy', width: 10 },
    { header: 'Agents', key: 'agents', width: 8 },
  ];

  console.log(formatTable(swarms, columns));
}
