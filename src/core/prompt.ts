import fs from 'node:fs/promises';
import path from 'node:path';
import { promptsDir, globalPromptsDir } from '../lib/paths.js';

export interface PromptEntry {
  name: string;
  source: 'local' | 'global';
}

export interface EnrichedEntry {
  name: string;
  description: string;
  variables: string[];
  source: 'local' | 'global';
  [key: string]: unknown;
}

async function readMdNames(dir: string): Promise<string[]> {
  try {
    const files = await fs.readdir(dir);
    return files.filter((f) => f.endsWith('.md')).map((f) => f.replace(/\.md$/, '')).sort();
  } catch {
    return [];
  }
}

export async function listPromptsWithSource(projectRoot: string): Promise<PromptEntry[]> {
  const localNames = await readMdNames(promptsDir(projectRoot));
  const globalNames = await readMdNames(globalPromptsDir());

  const seen = new Set<string>();
  const result: PromptEntry[] = [];

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

export async function enrichEntryMetadata(
  name: string,
  source: 'local' | 'global',
  localDir: string,
  globalDir: string,
): Promise<EnrichedEntry> {
  const dir = source === 'local' ? localDir : globalDir;
  const filePath = path.join(dir, `${name}.md`);
  const content = await fs.readFile(filePath, 'utf-8');
  const firstLine = content.split('\n').find((l) => l.trim().length > 0) ?? '';
  const description = firstLine.replace(/^#+\s*/, '').trim();
  const vars = [...content.matchAll(/\{\{(\w+)\}\}/g)].map((m) => m[1]);
  const uniqueVars = [...new Set(vars)];

  return { name, description, variables: uniqueVars, source };
}
