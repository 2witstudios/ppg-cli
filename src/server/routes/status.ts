import crypto from 'node:crypto';
import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { execa } from 'execa';
import { readManifest, resolveWorktree, updateManifest } from '../../core/manifest.js';
import { refreshAllAgentStatuses } from '../../core/agent.js';
import { computeLifecycle } from '../../core/lifecycle.js';
import { NotInitializedError, PpgError } from '../../lib/errors.js';
import { execaEnv } from '../../lib/env.js';

export interface StatusRouteOptions {
  projectRoot: string;
  bearerToken: string;
}

function timingSafeEqual(a: string, b: string): boolean {
  const aBuffer = Buffer.from(a);
  const bBuffer = Buffer.from(b);
  if (aBuffer.length !== bBuffer.length) return false;
  return crypto.timingSafeEqual(aBuffer, bBuffer);
}

function parseNumstatLine(line: string): { file: string; added: number; removed: number } {
  const [addedRaw = '', removedRaw = '', ...fileParts] = line.split('\t');

  const parseCount = (value: string): number => {
    if (value === '-') return 0;
    const parsed = Number.parseInt(value, 10);
    return Number.isNaN(parsed) ? 0 : parsed;
  };

  return {
    file: fileParts.join('\t'),
    added: parseCount(addedRaw),
    removed: parseCount(removedRaw),
  };
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
      let manifest;
      try {
        manifest = await readManifest(projectRoot);
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
          throw new NotInitializedError(projectRoot);
        }
        throw error;
      }

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
        .map((line) => parseNumstatLine(line));

      reply.send({
        worktreeId: wt.id,
        branch: wt.branch,
        baseBranch: wt.baseBranch,
        files,
      });
    },
  );
}
