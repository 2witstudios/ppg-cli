import fs from 'node:fs/promises';
import path from 'node:path';
import { getRepoRoot } from '../core/worktree.js';
import { listTemplatesWithSource } from '../core/template.js';
import { listSwarmsWithSource, loadSwarm } from '../core/swarm.js';
import { templatesDir, promptsDir, globalTemplatesDir, globalPromptsDir } from '../lib/paths.js';
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

  const entries = await listTemplatesWithSource(projectRoot);

  if (entries.length === 0) {
    console.log('No templates found in .ppg/templates/ or ~/.ppg/templates/');
    return;
  }

  const templates = await Promise.all(
    entries.map(async ({ name, source }) => {
      const dir = source === 'local' ? templatesDir(projectRoot) : globalTemplatesDir();
      const filePath = path.join(dir, `${name}.md`);
      const content = await fs.readFile(filePath, 'utf-8');
      const firstLine = content.split('\n').find((l) => l.trim().length > 0) ?? '';
      const description = firstLine.replace(/^#+\s*/, '').trim();

      const vars = [...content.matchAll(/\{\{(\w+)\}\}/g)].map((m) => m[1]);
      const uniqueVars = [...new Set(vars)];

      return { name, description, variables: uniqueVars, source };
    }),
  );

  if (options.json) {
    output({ templates }, true);
    return;
  }

  const columns: Column[] = [
    { header: 'Name', key: 'name', width: 20 },
    { header: 'Description', key: 'description', width: 36 },
    {
      header: 'Variables',
      key: 'variables',
      width: 24,
      format: (v) => (v as string[]).join(', '),
    },
    { header: 'Source', key: 'source', width: 8 },
  ];

  console.log(formatTable(templates, columns));
}

async function listSwarmsCommand(options: ListOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  const entries = await listSwarmsWithSource(projectRoot);

  if (entries.length === 0) {
    if (options.json) {
      output({ swarms: [] }, true);
    } else {
      console.log('No swarm templates found in .ppg/swarms/ or ~/.ppg/swarms/');
    }
    return;
  }

  const swarms = await Promise.all(
    entries.map(async ({ name, source }) => {
      const swarm = await loadSwarm(projectRoot, name);
      return {
        name,
        description: swarm.description,
        strategy: swarm.strategy,
        agents: swarm.agents.length,
        source,
      };
    }),
  );

  if (options.json) {
    output({ swarms }, true);
    return;
  }

  const columns: Column[] = [
    { header: 'Name', key: 'name', width: 20 },
    { header: 'Description', key: 'description', width: 34 },
    { header: 'Strategy', key: 'strategy', width: 10 },
    { header: 'Agents', key: 'agents', width: 8 },
    { header: 'Source', key: 'source', width: 8 },
  ];

  console.log(formatTable(swarms, columns));
}

interface PromptEntry {
  name: string;
  source: 'local' | 'global';
}

async function listPromptEntries(projectRoot: string): Promise<PromptEntry[]> {
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
  const result: PromptEntry[] = [];

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

async function listPromptsCommand(options: ListOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  const entries = await listPromptEntries(projectRoot);

  if (entries.length === 0) {
    if (options.json) {
      output({ prompts: [] }, true);
    } else {
      console.log('No prompts found in .ppg/prompts/ or ~/.ppg/prompts/');
    }
    return;
  }

  const prompts = await Promise.all(
    entries.map(async ({ name, source }) => {
      const dir = source === 'local' ? promptsDir(projectRoot) : globalPromptsDir();
      const filePath = path.join(dir, `${name}.md`);
      const content = await fs.readFile(filePath, 'utf-8');
      const firstLine = content.split('\n').find((l) => l.trim().length > 0) ?? '';
      const description = firstLine.replace(/^#+\s*/, '').trim();

      const vars = [...content.matchAll(/\{\{(\w+)\}\}/g)].map((m) => m[1]);
      const uniqueVars = [...new Set(vars)];

      return { name, description, variables: uniqueVars, source };
    }),
  );

  if (options.json) {
    output({ prompts }, true);
    return;
  }

  const columns: Column[] = [
    { header: 'Name', key: 'name', width: 20 },
    { header: 'Description', key: 'description', width: 36 },
    {
      header: 'Variables',
      key: 'variables',
      width: 24,
      format: (v) => (v as string[]).join(', '),
    },
    { header: 'Source', key: 'source', width: 8 },
  ];

  console.log(formatTable(prompts, columns));
}
