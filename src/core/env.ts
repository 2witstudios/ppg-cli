import fs from 'node:fs/promises';
import path from 'node:path';
import type { Config } from '../types/config.js';

export async function setupWorktreeEnv(
  projectRoot: string,
  wtPath: string,
  config: Config,
): Promise<void> {
  // Copy .env files
  for (const envFile of config.envFiles) {
    const src = path.join(projectRoot, envFile);
    const dest = path.join(wtPath, envFile);
    try {
      await fs.access(src);
      await fs.copyFile(src, dest);
    } catch {
      // Source env file doesn't exist, skip
    }
  }

  // Symlink node_modules
  if (config.symlinkNodeModules) {
    const src = path.join(projectRoot, 'node_modules');
    const dest = path.join(wtPath, 'node_modules');
    try {
      await fs.access(src);
      // Check if dest already exists
      try {
        await fs.lstat(dest);
        // Already exists, skip
      } catch {
        await fs.symlink(src, dest, 'dir');
      }
    } catch {
      // Source node_modules doesn't exist, skip
    }
  }
}

export async function teardownWorktreeEnv(wtPath: string): Promise<void> {
  // Remove node_modules symlink before worktree deletion
  const nmPath = path.join(wtPath, 'node_modules');
  try {
    const stat = await fs.lstat(nmPath);
    if (stat.isSymbolicLink()) {
      await fs.unlink(nmPath);
    }
  } catch {
    // Not a symlink or doesn't exist
  }
}
