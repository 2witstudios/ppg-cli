import { access } from 'node:fs/promises';
import path from 'node:path';
import { execa } from 'execa';
import { getRepoRoot } from '../core/worktree.js';
import { readManifest } from '../core/manifest.js';
import { manifestPath } from '../lib/paths.js';
import { NotInitializedError, PpgError } from '../lib/errors.js';
import { info } from '../lib/output.js';

export async function findDashboardBinary(projectRoot: string): Promise<string | null> {
  const localBuild = path.join(
    projectRoot,
    'PPG CLI',
    'build',
    'Build',
    'Products',
    'Release',
    'PPG CLI.app',
    'Contents',
    'MacOS',
    'PPG CLI',
  );

  try {
    await access(localBuild);
    return localBuild;
  } catch {
    // not found, fall through
  }

  const appsBuild = '/Applications/PPG CLI.app/Contents/MacOS/PPG CLI';
  try {
    await access(appsBuild);
    return appsBuild;
  } catch {
    // not found, fall through
  }

  try {
    const result = await execa('mdfind', [
      'kMDItemCFBundleIdentifier == "com.2wit.PPG-CLI"',
    ]);
    const appPath = result.stdout.trim().split('\n')[0];
    if (appPath) {
      const binaryPath = path.join(appPath, 'Contents', 'MacOS', 'PPG CLI');
      try {
        await access(binaryPath);
        return binaryPath;
      } catch {
        // found app but no binary
      }
    }
  } catch {
    // mdfind failed
  }

  return null;
}

export async function uiCommand(): Promise<void> {
  const projectRoot = await getRepoRoot();
  let manifest;
  try {
    manifest = await readManifest(projectRoot);
  } catch {
    throw new NotInitializedError(projectRoot);
  }

  const binaryPath = await findDashboardBinary(projectRoot);
  if (!binaryPath) {
    throw new PpgError(
      `Dashboard app not found. Install it with:\n  ppg install-dashboard\n\nOr build from source:\n  cd "PPG CLI" && xcodebuild -scheme "PPG CLI" -configuration Release -derivedDataPath build build`,
      'DASHBOARD_NOT_FOUND',
    );
  }

  const mPath = manifestPath(projectRoot);
  const proc = execa(binaryPath, [
    '--manifest-path', mPath,
    '--session-name', manifest.sessionName,
    '--project-root', projectRoot,
  ], {
    detached: true,
    stdio: 'ignore',
  });
  proc.unref();

  info(`Dashboard launched for ${manifest.sessionName}`);
}
