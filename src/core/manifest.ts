import fs from 'node:fs/promises';
import { manifestPath } from '../lib/paths.js';
import { getLockfile, getWriteFileAtomic } from '../lib/cjs-compat.js';
import { ManifestLockError, NotInitializedError } from '../lib/errors.js';
import type { Manifest, WorktreeEntry, AgentEntry } from '../types/manifest.js';

export function createEmptyManifest(projectRoot: string, sessionName: string): Manifest {
  const now = new Date().toISOString();
  return {
    version: 1,
    projectRoot,
    sessionName,
    agents: {},
    worktrees: {},
    createdAt: now,
    updatedAt: now,
  };
}

export async function readManifest(projectRoot: string): Promise<Manifest> {
  const mPath = manifestPath(projectRoot);
  const raw = await fs.readFile(mPath, 'utf-8');
  const manifest = JSON.parse(raw) as Manifest;
  // Backwards compat: older manifests lack top-level agents
  if (!manifest.agents) manifest.agents = {};
  return manifest;
}

export async function requireManifest(projectRoot: string): Promise<Manifest> {
  try {
    return await readManifest(projectRoot);
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
      throw new NotInitializedError(projectRoot);
    }
    throw err;
  }
}

export async function writeManifest(projectRoot: string, manifest: Manifest): Promise<void> {
  const writeFileAtomic = await getWriteFileAtomic();
  const mPath = manifestPath(projectRoot);
  manifest.updatedAt = new Date().toISOString();
  await writeFileAtomic(mPath, JSON.stringify(manifest, null, 2) + '\n');
}

export async function updateManifest(
  projectRoot: string,
  updater: (manifest: Manifest) => Manifest | Promise<Manifest>,
): Promise<Manifest> {
  const lockfile = await getLockfile();
  const mPath = manifestPath(projectRoot);
  let release: (() => Promise<void>) | undefined;

  try {
    release = await lockfile.lock(mPath, {
      stale: 10_000,
      retries: {
        retries: 5,
        minTimeout: 100,
        maxTimeout: 1000,
      },
    });
  } catch {
    throw new ManifestLockError();
  }

  try {
    const manifest = await readManifest(projectRoot);
    const updated = await updater(manifest);
    await writeManifest(projectRoot, updated);
    return updated;
  } finally {
    if (release) {
      await release();
    }
  }
}

function getWorktree(manifest: Manifest, id: string): WorktreeEntry | undefined {
  return manifest.worktrees[id];
}

function findWorktreeByName(manifest: Manifest, name: string): WorktreeEntry | undefined {
  return Object.values(manifest.worktrees).find(
    (wt) => wt.name === name || wt.branch === name,
  );
}

export function resolveWorktree(manifest: Manifest, ref: string): WorktreeEntry | undefined {
  return getWorktree(manifest, ref) ?? findWorktreeByName(manifest, ref);
}

export function findAgent(
  manifest: Manifest,
  agentId: string,
): { worktree: WorktreeEntry | undefined; agent: AgentEntry } | undefined {
  // Check master agents first
  const masterAgent = manifest.agents?.[agentId];
  if (masterAgent) {
    return { worktree: undefined, agent: masterAgent };
  }
  // Then check worktree agents
  for (const wt of Object.values(manifest.worktrees)) {
    const agent = wt.agents[agentId];
    if (agent) {
      return { worktree: wt, agent };
    }
  }
  return undefined;
}
