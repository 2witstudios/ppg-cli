import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { execa } from 'execa';
import { requireManifest, resolveWorktree, updateManifest } from '../../core/manifest.js';
import { refreshAllAgentStatuses } from '../../core/agent.js';
import { computeLifecycle } from '../../commands/status.js';
import { WorktreeNotFoundError } from '../../lib/errors.js';
import { execaEnv } from '../../lib/env.js';

export interface StatusRouteOptions {
  projectRoot: string;
  bearerToken: string;
}

function authenticate(token: string) {
  return async (request: FastifyRequest, reply: FastifyReply) => {
    const auth = request.headers.authorization;
    if (!auth || auth !== `Bearer ${token}`) {
      reply.code(401).send({ error: 'Unauthorized' });
    }
  };
}

export default async function statusRoutes(
  fastify: FastifyInstance,
  options: StatusRouteOptions,
): Promise<void> {
  const { projectRoot, bearerToken } = options;

  fastify.addHook('onRequest', authenticate(bearerToken));

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
      await requireManifest(projectRoot);
      const manifest = await updateManifest(projectRoot, async (m) => {
        return refreshAllAgentStatuses(m, projectRoot);
      });

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
