import fs from 'node:fs/promises';
import path from 'node:path';
import YAML from 'yaml';
import { swarmsDir, globalSwarmsDir } from '../lib/paths.js';
import { PpgError } from '../lib/errors.js';

export interface SwarmAgentEntry {
  prompt: string;
  agent?: string;
  vars?: Record<string, string>;
}

export interface SwarmTemplate {
  name: string;
  description: string;
  strategy: 'shared' | 'isolated';
  agents: SwarmAgentEntry[];
}

const SAFE_NAME = /^[\w-]+$/;

export interface SwarmEntry {
  name: string;
  source: 'local' | 'global';
}

async function readSwarmNames(dir: string): Promise<string[]> {
  try {
    const files = await fs.readdir(dir);
    return files
      .filter((f) => f.endsWith('.yaml') || f.endsWith('.yml'))
      .map((f) => f.replace(/\.ya?ml$/, ''))
      .sort();
  } catch {
    return [];
  }
}

export async function listSwarms(projectRoot: string): Promise<string[]> {
  const entries = await listSwarmsWithSource(projectRoot);
  return entries.map((e) => e.name);
}

export async function listSwarmsWithSource(projectRoot: string): Promise<SwarmEntry[]> {
  const localNames = await readSwarmNames(swarmsDir(projectRoot));
  const globalNames = await readSwarmNames(globalSwarmsDir());

  const seen = new Set<string>();
  const result: SwarmEntry[] = [];

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

async function trySwarmFile(dir: string, name: string): Promise<string | null> {
  const yamlPath = path.join(dir, `${name}.yaml`);
  try {
    await fs.access(yamlPath);
    return yamlPath;
  } catch {
    const ymlPath = path.join(dir, `${name}.yml`);
    try {
      await fs.access(ymlPath);
      return ymlPath;
    } catch {
      return null;
    }
  }
}

async function resolveSwarmFile(projectRoot: string, name: string): Promise<string | null> {
  // Project-local first
  const local = await trySwarmFile(swarmsDir(projectRoot), name);
  if (local) return local;

  // Global fallback
  return trySwarmFile(globalSwarmsDir(), name);
}

export async function loadSwarm(projectRoot: string, name: string): Promise<SwarmTemplate> {
  if (!SAFE_NAME.test(name)) {
    throw new PpgError(
      `Invalid swarm template name: "${name}" — must be alphanumeric, hyphens, or underscores`,
      'INVALID_ARGS',
    );
  }

  // Try project-local first, then global
  const filePath = await resolveSwarmFile(projectRoot, name);

  if (!filePath) {
    throw new PpgError(`Swarm template not found: ${name}`, 'INVALID_ARGS');
  }

  const raw = await fs.readFile(filePath, 'utf-8');
  const parsed = YAML.parse(raw) as SwarmTemplate;

  if (!parsed || typeof parsed !== 'object') {
    throw new PpgError(`Invalid swarm template: ${name} (empty or malformed YAML)`, 'INVALID_ARGS');
  }

  if (!parsed.name || !parsed.agents || !Array.isArray(parsed.agents)) {
    throw new PpgError(`Invalid swarm template: ${name} (missing name or agents)`, 'INVALID_ARGS');
  }

  if (!SAFE_NAME.test(parsed.name)) {
    throw new PpgError(
      `Invalid swarm name: "${parsed.name}" — must be alphanumeric, hyphens, or underscores`,
      'INVALID_ARGS',
    );
  }

  if (parsed.strategy && parsed.strategy !== 'shared' && parsed.strategy !== 'isolated') {
    throw new PpgError(
      `Invalid swarm strategy: ${parsed.strategy}. Must be 'shared' or 'isolated'`,
      'INVALID_ARGS',
    );
  }

  // Validate each agent has a valid prompt name
  for (let i = 0; i < parsed.agents.length; i++) {
    const agent = parsed.agents[i];
    if (!agent.prompt || typeof agent.prompt !== 'string') {
      throw new PpgError(
        `Invalid swarm template: ${name} — agent[${i}] missing prompt field`,
        'INVALID_ARGS',
      );
    }
    if (!SAFE_NAME.test(agent.prompt)) {
      throw new PpgError(
        `Invalid prompt name: "${agent.prompt}" — must be alphanumeric, hyphens, or underscores`,
        'INVALID_ARGS',
      );
    }
  }

  return {
    ...parsed,
    strategy: parsed.strategy ?? 'shared',
    description: parsed.description ?? '',
  };
}
