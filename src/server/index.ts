import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import { createRequire } from 'node:module';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import { agentRoutes } from './routes/agents.js';
import { globalPpgDir, globalServePidPath, globalServeJsonPath, globalServeLogPath } from '../lib/paths.js';
import { info, success } from '../lib/output.js';
import { createWsHandler, type WsHandler, type ClientState } from './ws/handler.js';
import { TerminalStreamer } from './ws/terminal.js';
import { startManifestWatcher, type ManifestWatcher } from './ws/watcher.js';
import { findAgent } from '../core/manifest.js';
import * as tmux from '../core/tmux.js';
import type { ServerEvent } from './ws/events.js';

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
  projectRoot?: string;
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

async function writeGlobalStateFile(state: ServeState): Promise<void> {
  const dir = globalPpgDir();
  await fs.mkdir(dir, { recursive: true });
  await fs.writeFile(globalServeJsonPath(), JSON.stringify(state, null, 2) + '\n', { mode: 0o600 });
}

async function writeGlobalPidFile(pid: number): Promise<void> {
  const dir = globalPpgDir();
  await fs.mkdir(dir, { recursive: true });
  await fs.writeFile(globalServePidPath(), String(pid) + '\n', { mode: 0o600 });
}

async function removeGlobalStateFiles(): Promise<void> {
  for (const filePath of [globalServeJsonPath(), globalServePidPath()]) {
    try {
      await fs.unlink(filePath);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== 'ENOENT') throw err;
    }
  }
}

/**
 * Resolve the project root from a `?project=<sessionName>` query param.
 * Falls back to a single project if only one is registered.
 */
async function resolveProjectRoot(projectQuery?: string): Promise<string> {
  const { listRegisteredProjects } = await import('../core/projects.js');
  const projects = await listRegisteredProjects();

  if (projectQuery) {
    const match = projects.find((p) => p.sessionName === projectQuery);
    if (match) return match.projectRoot;
    throw new Error(`No registered project with session name: ${projectQuery}`);
  }

  if (projects.length === 1) return projects[0].projectRoot;
  if (projects.length === 0) throw new Error('No projects registered. Run ppg init in a project first.');
  throw new Error('Multiple projects registered. Specify ?project=<sessionName>');
}

export async function startServer(options: ServeOptions): Promise<void> {
  const { port, host, token, json } = options;

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

  app.get('/health', async () => {
    return {
      status: 'ok',
      uptime: process.uptime(),
      version: packageVersion,
    };
  });

  // ---------- Multi-project routes ----------

  // GET /api/projects — list all registered projects with manifests
  app.get('/api/projects', async () => {
    const { listRegisteredProjects } = await import('../core/projects.js');
    const projects = await listRegisteredProjects();
    return { projects };
  });

  // POST /api/projects/register — register a project path
  app.post<{
    Body: { projectRoot: string };
  }>('/api/projects/register', {
    schema: {
      body: {
        type: 'object',
        required: ['projectRoot'],
        properties: { projectRoot: { type: 'string' } },
      },
    },
  }, async (request) => {
    const { registerProject } = await import('../core/projects.js');
    await registerProject(request.body.projectRoot);
    return { success: true };
  });

  // DELETE /api/projects/:sessionName — unregister a project
  app.delete<{
    Params: { sessionName: string };
  }>('/api/projects/:sessionName', async (request, reply) => {
    const { listRegisteredProjects, unregisterProject } = await import('../core/projects.js');
    const projects = await listRegisteredProjects();
    const match = projects.find((p) => p.sessionName === request.params.sessionName);
    if (!match) {
      return reply.code(404).send({ error: `No project with session name: ${request.params.sessionName}` });
    }
    await unregisterProject(match.projectRoot);
    return { success: true };
  });

  // GET /api/status — full manifest with live statuses (requires ?project or single project)
  app.get<{
    Querystring: { project?: string };
  }>('/api/status', async (request, reply) => {
    try {
      const projectRoot = await resolveProjectRoot(request.query.project);
      const { readManifest } = await import('../core/manifest.js');
      const { discoverUntrackedWindows } = await import('../core/agent.js');
      const manifest = await readManifest(projectRoot);
      const untrackedWindows = await discoverUntrackedWindows(manifest);
      return { ...manifest, untrackedWindows };
    } catch (err) {
      return reply.code(400).send({ error: err instanceof Error ? err.message : String(err) });
    }
  });

  // Register per-project route plugins with project resolution
  // Agent, worktree, config, and spawn routes all need a projectRoot

  // Helper: create a Fastify plugin that resolves projectRoot from query param
  const projectScopedPlugin = async (pluginFn: (app: Fastify.FastifyInstance, opts: { projectRoot: string }) => Promise<void>) => {
    return async (instance: Fastify.FastifyInstance) => {
      // Add a preHandler that resolves projectRoot for every request
      instance.addHook('preHandler', async (request, reply) => {
        try {
          const query = request.query as { project?: string };
          const projectRoot = await resolveProjectRoot(query.project);
          (request as any).projectRoot = projectRoot;
        } catch (err) {
          return reply.code(400).send({ error: err instanceof Error ? err.message : String(err) });
        }
      });

      // Decorate so routes can access it
      instance.decorateRequest('projectRoot', '');
    };
  };

  // For backwards compat + simplicity, resolve projectRoot per-request in route handlers
  // We pass a getter function instead of a static value
  const getProjectRoot = async (request: any): Promise<string> => {
    const query = request.query as { project?: string } | undefined;
    return resolveProjectRoot(query?.project);
  };

  // Decorate app with projectRoot getter for route plugins
  app.decorate('getProjectRoot', getProjectRoot);
  // Also provide static projectRoot for backward-compat (uses first registered project)
  app.decorate('projectRoot', options.projectRoot ?? '');

  // Register route plugins — they use projectRoot from opts or request
  // Agent routes need projectRoot at registration time, so we resolve it dynamically
  const { listRegisteredProjects } = await import('../core/projects.js');
  const projects = await listRegisteredProjects();
  const defaultProjectRoot = options.projectRoot ?? projects[0]?.projectRoot ?? '';

  await app.register(agentRoutes, { prefix: '/api', projectRoot: defaultProjectRoot });
  const { worktreeRoutes } = await import('./routes/worktrees.js');
  await app.register(worktreeRoutes, { prefix: '/api' });
  const { configRoutes } = await import('./routes/config.js');
  await app.register(configRoutes, { projectRoot: defaultProjectRoot });
  const spawnRoute = (await import('./routes/spawn.js')).default;
  await app.register(spawnRoute, { projectRoot: defaultProjectRoot });

  const lanAddress = detectLanAddress();

  // WebSocket infrastructure — variables declared here, wired after listen()
  let wsHandler: WsHandler | undefined;
  let streamer: TerminalStreamer | undefined;
  const watchers: ManifestWatcher[] = [];
  // Track per-client unsubscribe functions for terminal streaming
  const clientUnsubscribers = new Map<ClientState, Map<string, () => void>>();

  const shutdown = async (signal: string) => {
    if (!json) info(`Received ${signal}, shutting down...`);
    for (const watcher of watchers) watcher.stop();
    streamer?.destroy();
    if (wsHandler) await wsHandler.close();
    await removeGlobalStateFiles();
    await app.close();
    process.exit(0);
  };

  process.on('SIGTERM', () => { shutdown('SIGTERM').catch(() => process.exit(1)); });
  process.on('SIGINT', () => { shutdown('SIGINT').catch(() => process.exit(1)); });

  await app.listen({ port, host });

  // --- Wire WebSocket handler, terminal streamer, and manifest watchers ---

  streamer = new TerminalStreamer();

  /** Find an agent's tmuxTarget across all registered projects. */
  async function resolveAgentTmuxTarget(agentId: string): Promise<string> {
    // If agentId looks like a tmux target already (contains ':'), use it directly
    // This supports untracked windows where the tmuxTarget IS the identifier
    if (agentId.includes(':')) return agentId;

    const { listRegisteredProjects: listProjects } = await import('../core/projects.js');
    const allProjects = await listProjects();
    for (const project of allProjects) {
      const found = findAgent(project.manifest, agentId);
      if (found) return found.agent.tmuxTarget;
    }
    throw new Error(`Agent not found: ${agentId}`);
  }

  wsHandler = createWsHandler({
    server: app.server,
    validateToken: (t) => !token || t === token,
    onTerminalInput: async (agentId, data) => {
      const target = await resolveAgentTmuxTarget(agentId);
      await tmux.sendLiteral(target, data);
    },
    onTerminalResize: async (agentId, cols, rows) => {
      const target = await resolveAgentTmuxTarget(agentId);
      await tmux.resizePane(target, cols, rows);
    },
    onTerminalSubscribe: (client, agentId) => {
      resolveAgentTmuxTarget(agentId)
        .then((tmuxTarget) => {
          const unsub = streamer!.subscribe(agentId, tmuxTarget, (message) => {
            // Convert terminal streamer format to server event format
            const parsed = JSON.parse(message) as { type: string; agentId: string; lines: string[] };
            const event: ServerEvent = {
              type: 'terminal:output',
              agentId: parsed.agentId,
              data: parsed.lines.join('\n'),
            };
            wsHandler!.sendEvent(client, event);
          });
          // Store unsubscribe function for cleanup
          let clientMap = clientUnsubscribers.get(client);
          if (!clientMap) {
            clientMap = new Map();
            clientUnsubscribers.set(client, clientMap);
          }
          clientMap.set(agentId, unsub);
        })
        .catch(() => {
          wsHandler!.sendEvent(client, {
            type: 'error',
            code: 'AGENT_NOT_FOUND',
            message: `Could not subscribe to terminal for agent ${agentId}`,
          });
        });
    },
    onTerminalUnsubscribe: (client, agentId) => {
      const clientMap = clientUnsubscribers.get(client);
      if (clientMap) {
        const unsub = clientMap.get(agentId);
        if (unsub) {
          unsub();
          clientMap.delete(agentId);
        }
        if (clientMap.size === 0) {
          clientUnsubscribers.delete(client);
        }
      }
    },
  });

  // Start manifest watchers for each registered project
  for (const project of projects) {
    const watcher = startManifestWatcher(project.projectRoot, (event) => {
      if (!wsHandler) return;
      if (event.type === 'manifest:updated') {
        wsHandler.broadcast({
          type: 'manifest:updated',
          manifest: event.payload,
        });
      } else if (event.type === 'agent:status') {
        wsHandler.broadcast({
          type: 'agent:status',
          worktreeId: event.payload.worktreeId,
          agentId: event.payload.agentId,
          status: event.payload.status,
          worktreeStatus: event.payload.worktreeStatus,
        });
      }
    });
    watchers.push(watcher);
  }

  const state: ServeState = {
    pid: process.pid,
    port,
    host,
    lanAddress,
    startedAt: new Date().toISOString(),
    version: packageVersion,
  };

  await writeGlobalStateFile(state);
  await writeGlobalPidFile(process.pid);

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
