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
const pkg = require('../../package.json') as { version: string };

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
    const expected = Buffer.from(`Bearer ${token}`);
    app.addHook('onRequest', async (request, reply) => {
      if (request.url === '/health') return;
      const authHeader = request.headers.authorization ?? '';
      const supplied = Buffer.from(authHeader);
      if (expected.length !== supplied.length ||
          !crypto.timingSafeEqual(expected, supplied)) {
        reply.code(401).send({ error: 'Unauthorized' });
      }
    });
  }

  app.get('/health', async () => {
    return {
      status: 'ok',
      uptime: process.uptime(),
      version: pkg.version,
    };
  });

  // Register route plugins
  await app.register(agentRoutes, { prefix: '/api', projectRoot });

  const lanAddress = detectLanAddress();

  const shutdown = async (signal: string) => {
    if (!json) info(`Received ${signal}, shutting down...`);
    await removeStateFiles(projectRoot);
    await app.close();
    process.exit(0);
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));

  await app.listen({ port, host });

  const state: ServeState = {
    pid: process.pid,
    port,
    host,
    lanAddress,
    startedAt: new Date().toISOString(),
    version: pkg.version,
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
