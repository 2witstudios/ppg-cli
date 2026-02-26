import fs from 'node:fs/promises';
import path from 'node:path';
import { templatesDir, globalTemplatesDir } from '../lib/paths.js';

export interface TemplateEntry {
  name: string;
  source: 'local' | 'global';
}

async function readMdNames(dir: string): Promise<string[]> {
  try {
    const files = await fs.readdir(dir);
    return files.filter((f) => f.endsWith('.md')).map((f) => f.replace(/\.md$/, ''));
  } catch {
    return [];
  }
}

export async function listTemplates(projectRoot: string): Promise<string[]> {
  const entries = await listTemplatesWithSource(projectRoot);
  return entries.map((e) => e.name);
}

export async function listTemplatesWithSource(projectRoot: string): Promise<TemplateEntry[]> {
  const localNames = await readMdNames(templatesDir(projectRoot));
  const globalNames = await readMdNames(globalTemplatesDir());

  const seen = new Set<string>();
  const result: TemplateEntry[] = [];

  for (const name of localNames) {
    seen.add(name);
    result.push({ name, source: 'local' });
  }

  for (const name of globalNames) {
    if (!seen.has(name)) {
      result.push({ name, source: 'global' });
    }
  }

  return result;
}

export async function loadTemplate(projectRoot: string, name: string): Promise<string> {
  // Try project-local first
  const localPath = path.join(templatesDir(projectRoot), `${name}.md`);
  try {
    return await fs.readFile(localPath, 'utf-8');
  } catch {
    // Fall back to global
    const globalPath = path.join(globalTemplatesDir(), `${name}.md`);
    return fs.readFile(globalPath, 'utf-8');
  }
}

export interface TemplateContext {
  WORKTREE_PATH: string;
  BRANCH: string;
  AGENT_ID: string;
  RESULT_FILE: string;
  PROJECT_ROOT: string;
  TASK_NAME?: string;
  PROMPT?: string;
  [key: string]: string | undefined;
}

export function renderTemplate(content: string, context: TemplateContext): string {
  return content.replace(/\{\{(\w+)\}\}/g, (_match, key: string) => {
    return context[key] ?? `{{${key}}}`;
  });
}
