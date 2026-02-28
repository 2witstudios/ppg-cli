import fs from 'node:fs/promises';
import path from 'node:path';
import { projectsRegistryPath, globalPpgDir } from '../lib/paths.js';
import { readManifest } from './manifest.js';
import type { Manifest } from '../types/manifest.js';

export interface ProjectInfo {
  projectRoot: string;
  sessionName: string;
  manifest: Manifest;
}

interface RegistryEntry {
  projectRoot: string;
  registeredAt: string;
}

async function readRegistry(): Promise<RegistryEntry[]> {
  try {
    const raw = await fs.readFile(projectsRegistryPath(), 'utf-8');
    return JSON.parse(raw) as RegistryEntry[];
  } catch {
    return [];
  }
}

async function writeRegistry(entries: RegistryEntry[]): Promise<void> {
  const dir = globalPpgDir();
  await fs.mkdir(dir, { recursive: true });
  await fs.writeFile(projectsRegistryPath(), JSON.stringify(entries, null, 2) + '\n', 'utf-8');
}

export async function registerProject(projectRoot: string): Promise<void> {
  const resolved = path.resolve(projectRoot);
  const entries = await readRegistry();
  if (entries.some((e) => e.projectRoot === resolved)) return;
  entries.push({ projectRoot: resolved, registeredAt: new Date().toISOString() });
  await writeRegistry(entries);
}

export async function unregisterProject(projectRoot: string): Promise<void> {
  const resolved = path.resolve(projectRoot);
  const entries = await readRegistry();
  const filtered = entries.filter((e) => e.projectRoot !== resolved);
  if (filtered.length !== entries.length) {
    await writeRegistry(filtered);
  }
}

export async function listRegisteredProjects(): Promise<ProjectInfo[]> {
  const entries = await readRegistry();
  const projects: ProjectInfo[] = [];

  for (const entry of entries) {
    try {
      const manifest = await readManifest(entry.projectRoot);
      projects.push({
        projectRoot: entry.projectRoot,
        sessionName: manifest.sessionName,
        manifest,
      });
    } catch {
      // Project may have been deleted — skip silently
    }
  }

  return projects;
}

export async function getRegistryEntries(): Promise<RegistryEntry[]> {
  return readRegistry();
}
