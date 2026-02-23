import fs from 'node:fs/promises';
import path from 'node:path';
import { getRepoRoot } from '../core/worktree.js';
import { loadConfig } from '../core/config.js';
import { listTemplates } from '../core/template.js';
import { templatesDir } from '../lib/paths.js';
import { output, formatTable, type Column } from '../lib/output.js';

export interface ListOptions {
  json?: boolean;
}

export async function listCommand(type: string, options: ListOptions): Promise<void> {
  if (type !== 'templates') {
    throw new Error(`Unknown list type: ${type}. Available: templates`);
  }

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
