import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { startServer } from '../server/index.js';
import * as tmux from '../core/tmux.js';
import { globalPpgDir, globalServePidPath, globalServeJsonPath, globalServeLogPath } from '../lib/paths.js';
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

const SERVE_SESSION_NAME = 'ppg-serve';
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

async function isGlobalServeRunning(): Promise<boolean> {
  return (await getGlobalServePid()) !== null;
}

async function getGlobalServePid(): Promise<number | null> {
  const pidPath = globalServePidPath();
  let raw: string;
  try {
    raw = await fs.readFile(pidPath, 'utf-8');
  } catch {
    return null;
  }
  const pid = parseInt(raw.trim(), 10);
  if (isNaN(pid)) {
    try { await fs.unlink(pidPath); } catch { /* already gone */ }
    return null;
  }
  try {
    process.kill(pid, 0);
    return pid;
  } catch {
    try { await fs.unlink(pidPath); } catch { /* already gone */ }
    return null;
  }
}

async function getGlobalServeInfo(): Promise<{ port: number; host: string; startedAt: string } | null> {
  try {
    const raw = await fs.readFile(globalServeJsonPath(), 'utf-8');
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export async function serveStartCommand(options: ServeStartOptions): Promise<void> {
  const port = options.port!;
  const host = options.host!;

  if (!VALID_HOST.test(host)) {
    throw new PpgError(`Invalid host: "${host}"`, 'INVALID_ARGS');
  }

  // Auto-register current project if inside one
  try {
    const { getRepoRoot } = await import('../core/worktree.js');
    const { requireManifest } = await import('../core/manifest.js');
    const projectRoot = await getRepoRoot();
    await requireManifest(projectRoot);
    const { registerProject } = await import('../core/projects.js');
    await registerProject(projectRoot);
  } catch {
    // Not inside a ppg project — that's fine for global serve
  }

  // Check if already running
  if (await isGlobalServeRunning()) {
    const pid = await getGlobalServePid();
    const serveInfo = await getGlobalServeInfo();
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

  // Ensure global ppg dir exists
  await fs.mkdir(globalPpgDir(), { recursive: true });

  // Start daemon in a global tmux session
  await tmux.ensureSession(SERVE_SESSION_NAME);
  const windowTarget = await tmux.createWindow(SERVE_SESSION_NAME, SERVE_WINDOW_NAME, os.homedir());
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
  const pid = await getGlobalServePid();
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

  // Clean up PID and JSON files
  try { await fs.unlink(globalServePidPath()); } catch { /* already gone */ }
  try { await fs.unlink(globalServeJsonPath()); } catch { /* already gone */ }

  // Try to kill the tmux window too
  try {
    const windows = await tmux.listSessionWindows(SERVE_SESSION_NAME);
    const serveWindow = windows.find((w) => w.name === SERVE_WINDOW_NAME);
    if (serveWindow) {
      await tmux.killWindow(`${SERVE_SESSION_NAME}:${serveWindow.index}`);
    }
  } catch { /* best effort */ }

  if (options.json) {
    output({ success: true, pid }, true);
  } else {
    success(`Serve daemon stopped (PID: ${pid})`);
  }
}

export async function serveStatusCommand(options: ServeStatusOptions): Promise<void> {
  const running = await isGlobalServeRunning();
  const pid = running ? await getGlobalServePid() : null;
  const serveInfo = running ? await getGlobalServeInfo() : null;

  // Read global log
  const logPath = globalServeLogPath();
  let recentLines: string[] = [];
  try {
    const { createReadStream } = await import('node:fs');
    const readline = await import('node:readline');
    const rl = readline.createInterface({
      input: createReadStream(logPath, { encoding: 'utf-8' }),
      crlfDelay: Infinity,
    });
    const lines = options.lines ?? 20;
    const result: string[] = [];
    for await (const line of rl) {
      if (!line) continue;
      result.push(line);
      if (result.length > lines) result.shift();
    }
    recentLines = result;
  } catch {
    // No log file yet
  }

  if (options.json) {
    output({
      running,
      pid,
      ...(serveInfo ?? {}),
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

export async function serveRegisterCommand(pathArg: string | undefined, options: ServeOptions): Promise<void> {
  const projectRoot = pathArg ? path.resolve(pathArg) : process.cwd();

  // Verify the path is a ppg project
  const manifestFile = path.join(projectRoot, '.ppg', 'manifest.json');
  try {
    await fs.access(manifestFile);
  } catch {
    throw new PpgError(`No ppg project found at ${projectRoot} (missing .ppg/manifest.json)`, 'NOT_INITIALIZED');
  }

  const { registerProject } = await import('../core/projects.js');
  await registerProject(projectRoot);

  if (options.json) {
    output({ success: true, projectRoot, action: 'registered' }, true);
  } else {
    success(`Registered project: ${projectRoot}`);
  }
}

export async function serveUnregisterCommand(pathArg: string | undefined, options: ServeOptions): Promise<void> {
  const projectRoot = pathArg ? path.resolve(pathArg) : process.cwd();

  const { unregisterProject } = await import('../core/projects.js');
  await unregisterProject(projectRoot);

  if (options.json) {
    output({ success: true, projectRoot, action: 'unregistered' }, true);
  } else {
    success(`Unregistered project: ${projectRoot}`);
  }
}

export async function serveDaemonCommand(options: { port: number; host: string; token?: string }): Promise<void> {
  // Global daemon — no projectRoot required
  await startServer({ port: options.port, host: options.host, token: options.token });
}
