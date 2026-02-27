import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { execa } from 'execa';
import { requireManifest, updateManifest, resolveWorktree } from '../../core/manifest.js';
import { refreshAllAgentStatuses, killAgents } from '../../core/agent.js';
import { getCurrentBranch } from '../../core/worktree.js';
import { cleanupWorktree } from '../../core/cleanup.js';
import { PpgError, WorktreeNotFoundError, MergeFailedError, GhNotFoundError } from '../../lib/errors.js';
import { execaEnv } from '../../lib/env.js';
import { buildBodyFromResults } from '../../commands/pr.js';

// ------------------------------------------------------------------
// Fastify plugin — worktree action routes
// ------------------------------------------------------------------

interface WorktreeParams {
  id: string;
}

interface MergeBody {
  strategy?: 'squash' | 'no-ff';
  cleanup?: boolean;
  force?: boolean;
}

interface KillBody {
  force?: boolean;
}

interface PrBody {
  title?: string;
  body?: string;
  draft?: boolean;
}

function errorReply(reply: FastifyReply, err: unknown): void {
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
    reply.code(status).send({ error: err.message, code: err.code });
    return;
  }
  const message = err instanceof Error ? err.message : String(err);
  reply.code(500).send({ error: message });
}

export async function worktreeRoutes(app: FastifyInstance): Promise<void> {
  const projectRoot: string = (app as unknown as Record<string, unknown>)['projectRoot'] as string;

  // ----------------------------------------------------------------
  // POST /api/worktrees/:id/merge
  // ----------------------------------------------------------------
  app.post<{ Params: WorktreeParams; Body: MergeBody }>(
    '/worktrees/:id/merge',
    async (request, reply) => {
      try {
        const { id } = request.params;
        const { strategy = 'squash', cleanup = true, force = false } = request.body ?? {};

        await requireManifest(projectRoot);
        const manifest = await updateManifest(projectRoot, async (m) => {
          return refreshAllAgentStatuses(m, projectRoot);
        });

        const wt = resolveWorktree(manifest, id);
        if (!wt) throw new WorktreeNotFoundError(id);

        // Check all agents finished
        const incomplete = Object.values(wt.agents).filter((a) => a.status === 'running');
        if (incomplete.length > 0 && !force) {
          const ids = incomplete.map((a) => a.id).join(', ');
          throw new PpgError(
            `${incomplete.length} agent(s) still running: ${ids}. Use force: true to merge anyway.`,
            'AGENTS_RUNNING',
          );
        }

        // Set worktree status to merging
        await updateManifest(projectRoot, (m) => {
          if (m.worktrees[wt.id]) {
            m.worktrees[wt.id].status = 'merging';
          }
          return m;
        });

        try {
          const currentBranch = await getCurrentBranch(projectRoot);
          if (currentBranch !== wt.baseBranch) {
            await execa('git', ['checkout', wt.baseBranch], { ...execaEnv, cwd: projectRoot });
          }

          if (strategy === 'squash') {
            await execa('git', ['merge', '--squash', wt.branch], { ...execaEnv, cwd: projectRoot });
            await execa('git', ['commit', '-m', `ppg: merge ${wt.name} (${wt.branch})`], {
              ...execaEnv,
              cwd: projectRoot,
            });
          } else {
            await execa('git', ['merge', '--no-ff', wt.branch, '-m', `ppg: merge ${wt.name} (${wt.branch})`], {
              ...execaEnv,
              cwd: projectRoot,
            });
          }
        } catch (err) {
          await updateManifest(projectRoot, (m) => {
            if (m.worktrees[wt.id]) {
              m.worktrees[wt.id].status = 'failed';
            }
            return m;
          });
          throw new MergeFailedError(
            `Merge failed: ${err instanceof Error ? err.message : err}`,
          );
        }

        // Mark as merged
        await updateManifest(projectRoot, (m) => {
          if (m.worktrees[wt.id]) {
            m.worktrees[wt.id].status = 'merged';
            m.worktrees[wt.id].mergedAt = new Date().toISOString();
          }
          return m;
        });

        // Cleanup (no self-protection needed in server context)
        let cleaned = false;
        if (cleanup) {
          await cleanupWorktree(projectRoot, wt);
          cleaned = true;
        }

        return {
          success: true,
          worktreeId: wt.id,
          branch: wt.branch,
          baseBranch: wt.baseBranch,
          strategy,
          cleaned,
        };
      } catch (err) {
        errorReply(reply, err);
      }
    },
  );

  // ----------------------------------------------------------------
  // POST /api/worktrees/:id/kill
  // ----------------------------------------------------------------
  app.post<{ Params: WorktreeParams; Body: KillBody }>(
    '/worktrees/:id/kill',
    async (request, reply) => {
      try {
        const { id } = request.params;

        await requireManifest(projectRoot);
        const manifest = await updateManifest(projectRoot, async (m) => {
          return refreshAllAgentStatuses(m, projectRoot);
        });

        const wt = resolveWorktree(manifest, id);
        if (!wt) throw new WorktreeNotFoundError(id);

        const toKill = Object.values(wt.agents).filter((a) => a.status === 'running');
        const killedIds = toKill.map((a) => a.id);

        await killAgents(toKill);

        await updateManifest(projectRoot, (m) => {
          const mWt = m.worktrees[wt.id];
          if (mWt) {
            for (const agent of Object.values(mWt.agents)) {
              if (killedIds.includes(agent.id)) {
                agent.status = 'gone';
              }
            }
          }
          return m;
        });

        return {
          success: true,
          worktreeId: wt.id,
          killed: killedIds,
        };
      } catch (err) {
        errorReply(reply, err);
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
        const { id } = request.params;
        const { title, body, draft = false } = request.body ?? {};

        await requireManifest(projectRoot);
        const manifest = await updateManifest(projectRoot, async (m) => {
          return refreshAllAgentStatuses(m, projectRoot);
        });

        const wt = resolveWorktree(manifest, id);
        if (!wt) throw new WorktreeNotFoundError(id);

        // Verify gh is available
        try {
          await execa('gh', ['--version'], execaEnv);
        } catch {
          throw new GhNotFoundError();
        }

        // Push the worktree branch
        try {
          await execa('git', ['push', '-u', 'origin', wt.branch], { ...execaEnv, cwd: projectRoot });
        } catch (err) {
          throw new PpgError(
            `Failed to push branch ${wt.branch}: ${err instanceof Error ? err.message : err}`,
            'INVALID_ARGS',
          );
        }

        // Build PR title and body
        const prTitle = title ?? wt.name;
        const prBody = body ?? await buildBodyFromResults(Object.values(wt.agents));

        // Build gh pr create args
        const ghArgs = [
          'pr', 'create',
          '--head', wt.branch,
          '--base', wt.baseBranch,
          '--title', prTitle,
          '--body', prBody,
        ];
        if (draft) {
          ghArgs.push('--draft');
        }

        let prUrl: string;
        try {
          const result = await execa('gh', ghArgs, { ...execaEnv, cwd: projectRoot });
          prUrl = result.stdout.trim();
        } catch (err) {
          throw new PpgError(
            `Failed to create PR: ${err instanceof Error ? err.message : err}`,
            'INVALID_ARGS',
          );
        }

        // Store PR URL in manifest
        await updateManifest(projectRoot, (m) => {
          if (m.worktrees[wt.id]) {
            m.worktrees[wt.id].prUrl = prUrl;
          }
          return m;
        });

        return {
          success: true,
          worktreeId: wt.id,
          branch: wt.branch,
          baseBranch: wt.baseBranch,
          prUrl,
        };
      } catch (err) {
        errorReply(reply, err);
      }
    },
  );
}
