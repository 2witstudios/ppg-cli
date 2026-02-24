import { createWriteStream } from 'node:fs';
import { mkdir, cp, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pipeline } from 'node:stream/promises';
import { Readable } from 'node:stream';
import { execa } from 'execa';
import { output, info, success } from '../lib/output.js';
import { PgError } from '../lib/errors.js';

const REPO = '2witstudios/ppg-cli';
const ASSET_NAME = 'PPG-CLI-Dashboard.dmg';
const APP_NAME = 'PPG CLI.app';

async function getVersion(): Promise<string> {
  // Find package.json relative to this module — works in both dev (src/) and built (dist/)
  const pkgPath = new URL('../../package.json', import.meta.url);
  const raw = await readFile(pkgPath, 'utf-8');
  const pkg = JSON.parse(raw) as { version: string };
  return pkg.version;
}

export async function installDashboardCommand(options: {
  dir: string;
  json: boolean;
}): Promise<void> {
  const { dir, json } = options;

  try {
    const version = await getVersion();
    const tag = `v${version}`;
    const url = `https://github.com/${REPO}/releases/download/${tag}/${ASSET_NAME}`;

    if (!json) info(`Downloading dashboard ${tag} from GitHub Releases…`);

    const res = await fetch(url);
    if (!res.ok) {
      if (res.status === 404) {
        throw new PgError(
          `Dashboard release not found for ${tag}. The dashboard may not be available for this version yet.\nCheck: https://github.com/${REPO}/releases/tag/${tag}`,
          'DASHBOARD_NOT_FOUND',
        );
      }
      throw new PgError(
        `Failed to download dashboard: HTTP ${res.status} ${res.statusText}`,
        'DOWNLOAD_FAILED',
      );
    }

    // Download to temp directory
    const tmp = path.join(tmpdir(), `ppg-dashboard-${Date.now()}`);
    await mkdir(tmp, { recursive: true });
    const dmgPath = path.join(tmp, ASSET_NAME);

    const body = res.body;
    if (!body) throw new PgError('Empty response body', 'DOWNLOAD_FAILED');
    await pipeline(
      Readable.fromWeb(body as import('stream/web').ReadableStream),
      createWriteStream(dmgPath),
    );

    if (!json) info('Mounting…');

    // Mount DMG
    const mountResult = await execa('hdiutil', ['attach', dmgPath, '-nobrowse', '-quiet']);
    const mountLine = mountResult.stdout.trim().split('\n').pop() ?? '';
    const mountPoint = mountLine.split('\t').pop()?.trim();

    if (!mountPoint) {
      throw new PgError('Failed to mount DMG — could not determine mount point', 'INSTALL_FAILED');
    }

    try {
      const srcApp = path.join(mountPoint, APP_NAME);
      const destApp = path.join(dir, APP_NAME);

      if (!json) info('Installing…');

      // Remove existing installation if present
      await rm(destApp, { recursive: true, force: true });
      // Copy .app from mounted volume
      await cp(srcApp, destApp, { recursive: true });

      // Remove quarantine attribute
      try {
        await execa('xattr', ['-dr', 'com.apple.quarantine', destApp]);
      } catch {
        // Quarantine attribute may not exist — that's fine
      }

      if (json) {
        output({ success: true, version, path: destApp }, true);
      } else {
        success(`Dashboard ${tag} installed to ${destApp}`);
      }
    } finally {
      // Always unmount
      await execa('hdiutil', ['detach', mountPoint, '-quiet']).catch(() => {});
    }

    // Clean up temp
    await rm(tmp, { recursive: true, force: true });
  } catch (err) {
    if (err instanceof PgError) throw err;
    const message = err instanceof Error ? err.message : String(err);
    throw new PgError(`Dashboard installation failed: ${message}`, 'INSTALL_FAILED');
  }
}
