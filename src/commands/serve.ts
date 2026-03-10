import fs from 'node:fs/promises';
import os from 'node:os';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { getRepoRoot } from '../core/worktree.js';
import { requireManifest, readManifest } from '../core/manifest.js';
import { runServeDaemon, isServeRunning, getServePid, getServeInfo, readServeLog } from '../core/serve.js';
import { startServer } from '../server/index.js';
import * as tmux from '../core/tmux.js';
import { servePidPath, serveJsonPath } from '../lib/paths.js';
import { PpgError } from '../lib/errors.js';
import { output, info, success, warn } from '../lib/output.js';

export interface ServeStartOptions {
  port?: number;
  host?: string;
  token?: string;
  json?: boolean;
}

export interface ServeOptions {
  json?: boolean;
}

export interface ServeStatusOptions {
  lines?: number;
  json?: boolean;
}

const SERVE_WINDOW_NAME = 'ppg-serve';
const VALID_HOST = /^[\w.:-]+$/;

export function buildPairingUrl(params: {
  host: string;
  port: number;
  fingerprint: string;
  token: string;
}): string {
  const { host, port, fingerprint, token } = params;
  const url = new URL('ppg://connect');
  url.searchParams.set('host', host);
  url.searchParams.set('port', String(port));
  url.searchParams.set('ca', fingerprint);
  url.searchParams.set('token', token);
  return url.toString();
}

export function getLocalIp(): string {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name] ?? []) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address;
      }
    }
  }
  return '127.0.0.1';
}

export function verifyToken(provided: string, expected: string): boolean {
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

export async function serveStartCommand(options: ServeStartOptions): Promise<void> {
  const projectRoot = await getRepoRoot();
  await requireManifest(projectRoot);

  const port = options.port!;
  const host = options.host!;

  if (!VALID_HOST.test(host)) {
    throw new PpgError(`Invalid host: "${host}"`, 'INVALID_ARGS');
  }

  // Check if already running
  if (await isServeRunning(projectRoot)) {
    const pid = await getServePid(projectRoot);
    const serveInfo = await getServeInfo(projectRoot);
    if (options.json) {
      output({ success: false, error: 'Serve daemon is already running', pid, ...serveInfo }, true);
    } else {
      warn(`Serve daemon is already running (PID: ${pid})`);
      if (serveInfo) {
        info(`Listening on ${serveInfo.host}:${serveInfo.port}`);
      }
    }
    return;
  }

  // Start daemon in a tmux window
  const manifest = await readManifest(projectRoot);
  const sessionName = manifest.sessionName;
  await tmux.ensureSession(sessionName);

  const windowTarget = await tmux.createWindow(sessionName, SERVE_WINDOW_NAME, projectRoot);
  let command = `ppg serve _daemon --port ${port} --host ${host}`;
  if (options.token) {
    command += ` --token ${options.token}`;
  }
  await tmux.sendKeys(windowTarget, command);

  if (options.json) {
    output({
      success: true,
      tmuxWindow: windowTarget,
      port,
      host,
    }, true);
  } else {
    success(`Serve daemon starting in tmux window: ${windowTarget}`);
    info(`Configured for ${host}:${port}`);
    info(`Attach: tmux select-window -t ${windowTarget}`);
  }
}

export async function serveStopCommand(options: ServeOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  const pid = await getServePid(projectRoot);
  if (!pid) {
    if (options.json) {
      output({ success: false, error: 'Serve daemon is not running' }, true);
    } else {
      warn('Serve daemon is not running');
    }
    return;
  }

  // Kill the process
  try {
    process.kill(pid, 'SIGTERM');
  } catch {
    // Already dead
  }

  // Clean up PID and JSON files (daemon cleanup handler may not have run yet)
  try { await fs.unlink(servePidPath(projectRoot)); } catch { /* already gone */ }
  try { await fs.unlink(serveJsonPath(projectRoot)); } catch { /* already gone */ }

  // Try to kill the tmux window too
  try {
    const manifest = await readManifest(projectRoot);
    const windows = await tmux.listSessionWindows(manifest.sessionName);
    const serveWindow = windows.find((w) => w.name === SERVE_WINDOW_NAME);
    if (serveWindow) {
      await tmux.killWindow(`${manifest.sessionName}:${serveWindow.index}`);
    }
  } catch { /* best effort */ }

  if (options.json) {
    output({ success: true, pid }, true);
  } else {
    success(`Serve daemon stopped (PID: ${pid})`);
  }
}

export async function serveStatusCommand(options: ServeStatusOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  const running = await isServeRunning(projectRoot);
  const pid = running ? await getServePid(projectRoot) : null;
  const serveInfo = running ? await getServeInfo(projectRoot) : null;
  const recentLines = await readServeLog(projectRoot, options.lines ?? 20);

  if (options.json) {
    output({
      running,
      pid,
      ...(serveInfo ? { host: serveInfo.host, port: serveInfo.port, startedAt: serveInfo.startedAt } : {}),
      recentLog: recentLines,
    }, true);
    return;
  }

  if (running) {
    success(`Serve daemon is running (PID: ${pid})`);
    if (serveInfo) {
      info(`Listening on ${serveInfo.host}:${serveInfo.port}`);
      info(`Started at ${serveInfo.startedAt}`);
    }
  } else {
    warn('Serve daemon is not running');
  }

  if (recentLines.length > 0) {
    console.log('\nRecent log:');
    for (const line of recentLines) {
      console.log(`  ${line}`);
    }
  } else {
    info('No serve log entries yet');
  }
}

export async function serveDaemonCommand(options: { port: number; host: string; token?: string }): Promise<void> {
  const projectRoot = await getRepoRoot();
  await requireManifest(projectRoot);
  await runServeDaemon(projectRoot, options.port, options.host);
}
