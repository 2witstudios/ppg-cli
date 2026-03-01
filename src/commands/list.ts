import { getRepoRoot } from '../core/worktree.js';
import { listTemplatesWithSource } from '../core/template.js';
import { listPromptsWithSource, enrichEntryMetadata } from '../core/prompt.js';
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
    entries.map(({ name, source }) =>
      enrichEntryMetadata(name, source, templatesDir(projectRoot), globalTemplatesDir()),
    ),
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

async function listPromptsCommand(options: ListOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  const entries = await listPromptsWithSource(projectRoot);

  if (entries.length === 0) {
    if (options.json) {
      output({ prompts: [] }, true);
    } else {
      console.log('No prompts found in .ppg/prompts/ or ~/.ppg/prompts/');
    }
    return;
  }

  const prompts = await Promise.all(
    entries.map(({ name, source }) =>
      enrichEntryMetadata(name, source, promptsDir(projectRoot), globalPromptsDir()),
    ),
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
