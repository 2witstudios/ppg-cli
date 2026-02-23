import fs from 'node:fs/promises';
import path from 'node:path';
import { templatesDir } from '../lib/paths.js';

export async function listTemplates(projectRoot: string): Promise<string[]> {
  const dir = templatesDir(projectRoot);
  try {
    const files = await fs.readdir(dir);
    return files.filter((f) => f.endsWith('.md')).map((f) => f.replace(/\.md$/, ''));
  } catch {
    return [];
  }
}

export async function loadTemplate(projectRoot: string, name: string): Promise<string> {
  const dir = templatesDir(projectRoot);
  const filePath = path.join(dir, `${name}.md`);
  return fs.readFile(filePath, 'utf-8');
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
