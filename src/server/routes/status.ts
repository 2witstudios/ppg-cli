import crypto from 'node:crypto';
import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { execa } from 'execa';
import { readManifest, resolveWorktree, updateManifest } from '../../core/manifest.js';
import { refreshAllAgentStatuses } from '../../core/agent.js';
import { computeLifecycle } from '../../core/lifecycle.js';
import { PpgError } from '../../lib/errors.js';
import { execaEnv } from '../../lib/env.js';

export interface StatusRouteOptions {
  projectRoot: string;
  bearerToken: string;
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b));
}

function authenticate(token: string) {
  const expected = `Bearer ${token}`;
  return async (request: FastifyRequest, reply: FastifyReply) => {
    const auth = request.headers.authorization ?? '';
    if (!timingSafeEqual(auth, expected)) {
      return reply.code(401).send({ error: 'Unauthorized' });
    }
  };
}

const ppgErrorToStatus: Record<string, number> = {
  NOT_INITIALIZED: 503,
  MANIFEST_LOCK: 503,
  WORKTREE_NOT_FOUND: 404,
  AGENT_NOT_FOUND: 404,
};

export default async function statusRoutes(
  fastify: FastifyInstance,
  options: StatusRouteOptions,
): Promise<void> {
  const { projectRoot, bearerToken } = options;

  fastify.addHook('onRequest', authenticate(bearerToken));

  fastify.setErrorHandler((error, _request, reply) => {
    if (error instanceof PpgError) {
      const status = ppgErrorToStatus[error.code] ?? 500;
      reply.code(status).send({ error: error.message, code: error.code });
      return;
    }
    reply.code(500).send({ error: 'Internal server error' });
  });

  // GET /api/status — full manifest with live agent statuses
  fastify.get('/api/status', async (_request, reply) => {
    const manifest = await updateManifest(projectRoot, async (m) => {
      return refreshAllAgentStatuses(m, projectRoot);
    });

    const worktrees = Object.fromEntries(
      Object.values(manifest.worktrees).map((wt) => [
        wt.id,
        { ...wt, lifecycle: computeLifecycle(wt) },
      ]),
    );

    reply.send({
      session: manifest.sessionName,
      worktrees,
    });
  });

  // GET /api/worktrees/:id — single worktree detail with refreshed statuses
  fastify.get<{ Params: { id: string } }>(
    '/api/worktrees/:id',
    async (request, reply) => {
      const manifest = await updateManifest(projectRoot, async (m) => {
        return refreshAllAgentStatuses(m, projectRoot);
      });

      const wt = resolveWorktree(manifest, request.params.id);
      if (!wt) {
        reply.code(404).send({ error: `Worktree not found: ${request.params.id}` });
        return;
      }

      reply.send({ ...wt, lifecycle: computeLifecycle(wt) });
    },
  );

  // GET /api/worktrees/:id/diff — branch diff (numstat format)
  fastify.get<{ Params: { id: string } }>(
    '/api/worktrees/:id/diff',
    async (request, reply) => {
      const manifest = await readManifest(projectRoot);

      const wt = resolveWorktree(manifest, request.params.id);
      if (!wt) {
        reply.code(404).send({ error: `Worktree not found: ${request.params.id}` });
        return;
      }

      const diffRange = `${wt.baseBranch}...${wt.branch}`;
      const result = await execa('git', ['diff', '--numstat', diffRange], {
        ...execaEnv,
        cwd: projectRoot,
      });

      const files = result.stdout
        .trim()
        .split('\n')
        .filter(Boolean)
        .map((line) => {
          const [added, removed, file] = line.split('\t');
          return {
            file,
            added: added === '-' ? 0 : parseInt(added, 10),
            removed: removed === '-' ? 0 : parseInt(removed, 10),
          };
        });

      reply.send({
        worktreeId: wt.id,
        branch: wt.branch,
        baseBranch: wt.baseBranch,
        files,
      });
    },
  );
}
