import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { spawnNewWorktree, resolvePromptText } from '../../core/spawn.js';
import { PpgError } from '../../lib/errors.js';

export interface SpawnRequestBody {
  name: string;
  agent?: string;
  prompt?: string;
  template?: string;
  vars?: Record<string, string>;
  base?: string;
  count?: number;
}

export interface SpawnResponseBody {
  worktreeId: string;
  name: string;
  branch: string;
  agents: Array<{
    id: string;
    tmuxTarget: string;
    sessionId?: string;
  }>;
}

const spawnBodySchema = {
  type: 'object' as const,
  required: ['name'],
  properties: {
    name: { type: 'string' as const, minLength: 1 },
    agent: { type: 'string' as const },
    prompt: { type: 'string' as const },
    template: { type: 'string' as const },
    vars: {
      type: 'object' as const,
      additionalProperties: { type: 'string' as const },
    },
    base: { type: 'string' as const },
    count: { type: 'integer' as const, minimum: 1, maximum: 20 },
  },
  additionalProperties: false,
};

// Shell metacharacters that could be injected via tmux send-keys
const SHELL_META_RE = /[`$\\!;|&()<>{}[\]"'\n\r]/;

function validateVars(vars: Record<string, string>): void {
  for (const [key, value] of Object.entries(vars)) {
    if (SHELL_META_RE.test(key)) {
      throw new PpgError(
        `Var key "${key}" contains shell metacharacters`,
        'INVALID_ARGS',
      );
    }
    if (SHELL_META_RE.test(value)) {
      throw new PpgError(
        `Var value for "${key}" contains shell metacharacters`,
        'INVALID_ARGS',
      );
    }
  }
}

function statusForPpgError(code: string): number {
  switch (code) {
    case 'INVALID_ARGS':
      return 400;
    case 'NOT_INITIALIZED':
      return 409;
    default:
      return 500;
  }
}

export interface SpawnRouteOptions {
  projectRoot: string;
}

export default async function spawnRoute(
  app: FastifyInstance,
  opts: SpawnRouteOptions,
): Promise<void> {
  const { projectRoot } = opts;

  app.post(
    '/api/spawn',
    { schema: { body: spawnBodySchema } },
    async (
      request: FastifyRequest<{ Body: SpawnRequestBody }>,
      reply: FastifyReply,
    ) => {
      try {
        const body = request.body;

        // Validate vars for shell safety before any side effects
        if (body.vars) {
          validateVars(body.vars);
        }

        const promptText = await resolvePromptText(
          { prompt: body.prompt, template: body.template },
          projectRoot,
        );

        const result = await spawnNewWorktree({
          projectRoot,
          name: body.name,
          promptText,
          userVars: body.vars,
          agentName: body.agent,
          baseBranch: body.base,
          count: body.count,
        });

        const response: SpawnResponseBody = {
          worktreeId: result.worktreeId,
          name: result.name,
          branch: result.branch,
          agents: result.agents.map((a) => ({
            id: a.id,
            tmuxTarget: a.tmuxTarget,
            sessionId: a.sessionId,
          })),
        };

        return reply.status(201).send(response);
      } catch (err) {
        if (err instanceof PpgError) {
          return reply.status(statusForPpgError(err.code)).send({
            message: err.message,
            code: err.code,
          });
        }

        return reply.status(500).send({
          message: err instanceof Error ? err.message : 'Internal server error',
        });
      }
    },
  );
}
