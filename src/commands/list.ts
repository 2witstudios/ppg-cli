import fs from 'node:fs/promises';
import path from 'node:path';
import { getRepoRoot } from '../core/worktree.js';
import { listTemplates } from '../core/template.js';
import { listSwarms, loadSwarm } from '../core/swarm.js';
import { templatesDir, promptsDir } from '../lib/paths.js';
import { PpgError } from '../lib/errors.js';
import { output, formatTable, type Column } from '../lib/output.js';

export interface ListOptions {
  json?: boolean;
}

export async function listCommand(type: string, options: ListOptions): Promise<void> {
  if (type === 'templates') {
    await listTemplatesCommand(options);
  } else if (type === 'swarms') {
    await listSwarmsCommand(options);
  } else if (type === 'prompts') {
    await listPromptsCommand(options);
  } else {
    throw new PpgError(`Unknown list type: ${type}. Available: templates, swarms, prompts`, 'INVALID_ARGS');
  }
}

async function listTemplatesCommand(options: ListOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  const templateNames = await listTemplates(projectRoot);

  if (templateNames.length === 0) {
    console.log('No templates found in .ppg/templates/');
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
    if (options.json) {
      output({ swarms: [] }, true);
    } else {
      console.log('No swarm templates found in .ppg/swarms/');
    }
    return;
  }

  const swarms = await Promise.all(
    swarmNames.map(async (name) => {
      const swarm = await loadSwarm(projectRoot, name);
      return {
        name,
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

async function listPromptsCommand(options: ListOptions): Promise<void> {
  const projectRoot = await getRepoRoot();
  const dir = promptsDir(projectRoot);

  let files: string[];
  try {
    files = (await fs.readdir(dir)).filter((f) => f.endsWith('.md')).sort();
  } catch {
    files = [];
  }

  if (files.length === 0) {
    if (options.json) {
      output({ prompts: [] }, true);
    } else {
      console.log('No prompts found in .ppg/prompts/');
    }
    return;
  }

  const prompts = await Promise.all(
    files.map(async (file) => {
      const name = file.replace(/\.md$/, '');
      const filePath = path.join(dir, file);
      const content = await fs.readFile(filePath, 'utf-8');
      const firstLine = content.split('\n').find((l) => l.trim().length > 0) ?? '';
      const description = firstLine.replace(/^#+\s*/, '').trim();

      const vars = [...content.matchAll(/\{\{(\w+)\}\}/g)].map((m) => m[1]);
      const uniqueVars = [...new Set(vars)];

      return { name, description, variables: uniqueVars };
    }),
  );

  if (options.json) {
    output({ prompts }, true);
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

  console.log(formatTable(prompts, columns));
}
