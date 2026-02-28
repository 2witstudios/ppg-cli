import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { updateManifest, resolveWorktree } from '../../core/manifest.js';
import { refreshAllAgentStatuses } from '../../core/agent.js';
import { mergeWorktree } from '../../core/merge.js';
import { killWorktreeAgents } from '../../core/kill.js';
import { createWorktreePr } from '../../core/pr.js';
import { PpgError, WorktreeNotFoundError } from '../../lib/errors.js';

// ------------------------------------------------------------------
// Fastify plugin — worktree action routes
// ------------------------------------------------------------------

declare module 'fastify' {
  interface FastifyInstance {
    projectRoot: string;
    getProjectRoot: (request: FastifyRequest) => Promise<string>;
  }
}

interface WorktreeParams {
  id: string;
}

interface MergeBody {
  strategy?: 'squash' | 'no-ff';
  cleanup?: boolean;
  force?: boolean;
}

interface PrBody {
  title?: string;
  body?: string;
  draft?: boolean;
}

function errorReply(reply: FastifyReply, err: unknown): FastifyReply {
  if (err instanceof PpgError) {
    const statusMap: Record<string, number> = {
      WORKTREE_NOT_FOUND: 404,
      AGENT_NOT_FOUND: 404,
      NOT_INITIALIZED: 400,
      AGENTS_RUNNING: 409,
      MERGE_FAILED: 500,
      GH_NOT_FOUND: 502,
      INVALID_ARGS: 400,
    };
    const status = statusMap[err.code] ?? 500;
    return reply.code(status).send({ error: err.message, code: err.code });
  }
  const message = err instanceof Error ? err.message : String(err);
  return reply.code(500).send({ error: message });
}

async function resolveWorktreeFromRequest(
  projectRoot: string,
  id: string,
) {
  const manifest = await updateManifest(projectRoot, async (m) => {
    return refreshAllAgentStatuses(m, projectRoot);
  });

  const wt = resolveWorktree(manifest, id);
  if (!wt) throw new WorktreeNotFoundError(id);
  return wt;
}

export async function worktreeRoutes(app: FastifyInstance): Promise<void> {
  const resolveRoot = async (request: FastifyRequest): Promise<string> => {
    if (app.getProjectRoot) {
      try { return await app.getProjectRoot(request); } catch { /* fall through */ }
    }
    return app.projectRoot;
  };

  // ----------------------------------------------------------------
  // POST /api/worktrees/:id/merge
  // ----------------------------------------------------------------
  app.post<{ Params: WorktreeParams; Body: MergeBody }>(
    '/worktrees/:id/merge',
    async (request, reply) => {
      try {
        const projectRoot = await resolveRoot(request);
        const wt = await resolveWorktreeFromRequest(projectRoot, request.params.id);
        const { strategy, cleanup, force } = request.body ?? {};

        const result = await mergeWorktree(projectRoot, wt, { strategy, cleanup, force });

        return { success: true, ...result };
      } catch (err) {
        return errorReply(reply, err);
      }
    },
  );

  // ----------------------------------------------------------------
  // POST /api/worktrees/:id/kill
  // ----------------------------------------------------------------
  app.post<{ Params: WorktreeParams }>(
    '/worktrees/:id/kill',
    async (request, reply) => {
      try {
        const projectRoot = await resolveRoot(request);
        const wt = await resolveWorktreeFromRequest(projectRoot, request.params.id);

        const result = await killWorktreeAgents(projectRoot, wt);

        return { success: true, ...result };
      } catch (err) {
        return errorReply(reply, err);
      }
    },
  );

  // ----------------------------------------------------------------
  // POST /api/worktrees/:id/pr
  // ----------------------------------------------------------------
  app.post<{ Params: WorktreeParams; Body: PrBody }>(
    '/worktrees/:id/pr',
    async (request, reply) => {
      try {
        const projectRoot = await resolveRoot(request);
        const wt = await resolveWorktreeFromRequest(projectRoot, request.params.id);
        const { title, body, draft } = request.body ?? {};

        const result = await createWorktreePr(projectRoot, wt, { title, body, draft });

        return { success: true, ...result };
      } catch (err) {
        return errorReply(reply, err);
      }
    },
  );
}
