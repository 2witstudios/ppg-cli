import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import { createRequire } from 'node:module';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import { agentRoutes } from './routes/agents.js';
import { serveStatePath, servePidPath } from '../lib/paths.js';
import { info, success } from '../lib/output.js';

const require = createRequire(import.meta.url);
const PACKAGE_JSON_PATHS = ['../../package.json', '../package.json'] as const;

function getPackageVersion(): string {
  for (const packageJsonPath of PACKAGE_JSON_PATHS) {
    try {
      const pkg = require(packageJsonPath) as { version?: unknown };
      if (typeof pkg.version === 'string') return pkg.version;
    } catch {
      // Fall through and try alternate path.
    }
  }
  throw new Error('Unable to resolve package version');
}

const packageVersion = getPackageVersion();

export interface ServeOptions {
  projectRoot: string;
  port: number;
  host: string;
  token?: string;
  json?: boolean;
}

export interface ServeState {
  pid: number;
  port: number;
  host: string;
  lanAddress?: string;
  startedAt: string;
  version: string;
}

export function detectLanAddress(): string | undefined {
  const interfaces = os.networkInterfaces();
  for (const addrs of Object.values(interfaces)) {
    if (!addrs) continue;
    for (const addr of addrs) {
      if (addr.family === 'IPv4' && !addr.internal) {
        return addr.address;
      }
    }
  }
  return undefined;
}

export function timingSafeTokenMatch(header: string | undefined, expected: string): boolean {
  const expectedValue = `Bearer ${expected}`;
  if (!header || header.length !== expectedValue.length) return false;
  const headerBuffer = Buffer.from(header);
  const expectedBuffer = Buffer.from(expectedValue);
  if (headerBuffer.length !== expectedBuffer.length) return false;
  return crypto.timingSafeEqual(
    headerBuffer,
    expectedBuffer,
  );
}

async function writeStateFile(projectRoot: string, state: ServeState): Promise<void> {
  const statePath = serveStatePath(projectRoot);
  await fs.writeFile(statePath, JSON.stringify(state, null, 2) + '\n', { mode: 0o600 });
}

async function writePidFile(projectRoot: string, pid: number): Promise<void> {
  const pidPath = servePidPath(projectRoot);
  await fs.writeFile(pidPath, String(pid) + '\n', { mode: 0o600 });
}

async function removeStateFiles(projectRoot: string): Promise<void> {
  for (const filePath of [serveStatePath(projectRoot), servePidPath(projectRoot)]) {
    try {
      await fs.unlink(filePath);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== 'ENOENT') throw err;
    }
  }
}

export async function startServer(options: ServeOptions): Promise<void> {
  const { projectRoot, port, host, token, json } = options;

  const app = Fastify({ logger: false });

  await app.register(cors, { origin: true });

  if (token) {
    app.addHook('onRequest', async (request, reply) => {
      if (request.url === '/health') return;
      if (!timingSafeTokenMatch(request.headers.authorization, token)) {
        return reply.code(401).send({ error: 'Unauthorized' });
      }
    });
  }

  // Decorate with projectRoot so routes can access it
  app.decorate('projectRoot', projectRoot);

  app.get('/health', async () => {
    return {
      status: 'ok',
      uptime: process.uptime(),
      version: packageVersion,
    };
  });

  // GET /api/status — full manifest with live statuses
  app.get('/api/status', async () => {
    const { readManifest } = await import('../core/manifest.js');
    const manifest = await readManifest(projectRoot);
    return manifest;
  });

  // Register route plugins
  await app.register(agentRoutes, { prefix: '/api', projectRoot });
  const { worktreeRoutes } = await import('./routes/worktrees.js');
  await app.register(worktreeRoutes, { prefix: '/api' });
  const { configRoutes } = await import('./routes/config.js');
  await app.register(configRoutes, { projectRoot });
  const spawnRoute = (await import('./routes/spawn.js')).default;
  await app.register(spawnRoute, { projectRoot });

  const lanAddress = detectLanAddress();

  const shutdown = async (signal: string) => {
    if (!json) info(`Received ${signal}, shutting down...`);
    await removeStateFiles(projectRoot);
    await app.close();
    process.exit(0);
  };

  process.on('SIGTERM', () => { shutdown('SIGTERM').catch(() => process.exit(1)); });
  process.on('SIGINT', () => { shutdown('SIGINT').catch(() => process.exit(1)); });

  await app.listen({ port, host });

  const state: ServeState = {
    pid: process.pid,
    port,
    host,
    lanAddress,
    startedAt: new Date().toISOString(),
    version: packageVersion,
  };

  await writeStateFile(projectRoot, state);
  await writePidFile(projectRoot, process.pid);

  if (json) {
    console.log(JSON.stringify(state));
  } else {
    success(`Server listening on http://${host}:${port}`);
    if (lanAddress) {
      info(`LAN address: http://${lanAddress}:${port}`);
    }
    if (token) {
      info('Bearer token authentication enabled');
    }
  }
}
