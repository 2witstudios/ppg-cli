import fs from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { serveJsonPath, serveLogPath, servePidPath, logsDir } from '../lib/paths.js';

export interface ServeInfo {
  pid: number;
  port: number;
  host: string;
  startedAt: string;
}

export async function runServeDaemon(projectRoot: string, port: number, host: string): Promise<void> {
  const pidPath = servePidPath(projectRoot);
  const jsonPath = serveJsonPath(projectRoot);

  // Write PID file
  await fs.mkdir(path.dirname(pidPath), { recursive: true });
  await fs.writeFile(pidPath, String(process.pid), 'utf-8');

  // Write serve.json with connection info
  const info: ServeInfo = {
    pid: process.pid,
    port,
    host,
    startedAt: new Date().toISOString(),
  };
  await fs.writeFile(jsonPath, JSON.stringify(info, null, 2), 'utf-8');

  // Ensure logs directory
  await fs.mkdir(logsDir(projectRoot), { recursive: true });

  await logServe(projectRoot, `Serve daemon starting (PID: ${process.pid})`);
  await logServe(projectRoot, `Listening on ${host}:${port}`);

  // Clean shutdown on SIGTERM/SIGINT
  const cleanup = async () => {
    await logServe(projectRoot, 'Serve daemon stopping');
    try { await fs.unlink(pidPath); } catch { /* already gone */ }
    try { await fs.unlink(jsonPath); } catch { /* already gone */ }
    process.exit(0);
  };
  process.on('SIGTERM', cleanup);
  process.on('SIGINT', cleanup);

  // Placeholder: the actual HTTP server will be implemented by issue #63.
  // For now, keep the daemon alive so the lifecycle works end-to-end.
  await logServe(projectRoot, 'Serve daemon ready (waiting for server implementation)');

  // Keep alive
  await new Promise(() => {});
}

export async function isServeRunning(projectRoot: string): Promise<boolean> {
  return (await getServePid(projectRoot)) !== null;
}

export async function getServePid(projectRoot: string): Promise<number | null> {
  const pidPath = servePidPath(projectRoot);
  let raw: string;
  try {
    raw = await fs.readFile(pidPath, 'utf-8');
  } catch {
    return null;
  }
  const pid = parseInt(raw, 10);
  if (isNaN(pid)) {
    await cleanupPidFile(pidPath);
    return null;
  }
  try {
    process.kill(pid, 0);
    return pid;
  } catch {
    await cleanupPidFile(pidPath);
    return null;
  }
}

export async function getServeInfo(projectRoot: string): Promise<ServeInfo | null> {
  const jsonPath = serveJsonPath(projectRoot);
  try {
    const raw = await fs.readFile(jsonPath, 'utf-8');
    return JSON.parse(raw) as ServeInfo;
  } catch {
    return null;
  }
}

async function cleanupPidFile(pidPath: string): Promise<void> {
  try { await fs.unlink(pidPath); } catch { /* already gone */ }
}

export async function logServe(projectRoot: string, message: string): Promise<void> {
  const logPath = serveLogPath(projectRoot);
  const timestamp = new Date().toISOString();
  const line = `[${timestamp}] ${message}\n`;

  process.stdout.write(line);

  try {
    await fs.appendFile(logPath, line, 'utf-8');
  } catch {
    await fs.mkdir(logsDir(projectRoot), { recursive: true });
    await fs.appendFile(logPath, line, 'utf-8');
  }
}

export async function readServeLog(projectRoot: string, lines: number = 20): Promise<string[]> {
  const logPath = serveLogPath(projectRoot);
  try {
    await fs.access(logPath);
  } catch {
    return [];
  }
  const result: string[] = [];
  const rl = readline.createInterface({
    input: createReadStream(logPath, { encoding: 'utf-8' }),
    crlfDelay: Infinity,
  });
  for await (const line of rl) {
    if (!line) continue;
    result.push(line);
    if (result.length > lines) {
      result.shift();
    }
  }
  return result;
}
