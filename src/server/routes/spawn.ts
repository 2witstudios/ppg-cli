import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { loadConfig, resolveAgentConfig } from '../../core/config.js';
import { readManifest, updateManifest } from '../../core/manifest.js';
import { getRepoRoot, getCurrentBranch, createWorktree } from '../../core/worktree.js';
import { setupWorktreeEnv } from '../../core/env.js';
import { loadTemplate, renderTemplate, type TemplateContext } from '../../core/template.js';
import { spawnAgent } from '../../core/agent.js';
import * as tmux from '../../core/tmux.js';
import { worktreeId as genWorktreeId, agentId as genAgentId, sessionId as genSessionId } from '../../lib/id.js';
import { PpgError } from '../../lib/errors.js';
import { normalizeName } from '../../lib/name.js';
import type { WorktreeEntry, AgentEntry } from '../../types/manifest.js';

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

async function resolvePrompt(
  body: SpawnRequestBody,
  projectRoot: string,
): Promise<string> {
  if (body.prompt) return body.prompt;

  if (body.template) {
    return loadTemplate(projectRoot, body.template);
  }

  throw new PpgError(
    'Either "prompt" or "template" is required',
    'INVALID_ARGS',
  );
}

export default async function spawnRoute(app: FastifyInstance): Promise<void> {
  app.post(
    '/api/spawn',
    { schema: { body: spawnBodySchema } },
    async (
      request: FastifyRequest<{ Body: SpawnRequestBody }>,
      reply: FastifyReply,
    ) => {
      const body = request.body;
      const projectRoot = await getRepoRoot();
      const config = await loadConfig(projectRoot);
      const agentConfig = resolveAgentConfig(config, body.agent);
      const count = body.count ?? 1;
      const userVars = body.vars ?? {};

      const promptText = await resolvePrompt(body, projectRoot);

      const baseBranch = body.base ?? await getCurrentBranch(projectRoot);
      const wtId = genWorktreeId();
      const name = normalizeName(body.name, wtId);
      const branchName = `ppg/${name}`;

      // Create git worktree
      const wtPath = await createWorktree(projectRoot, wtId, {
        branch: branchName,
        base: baseBranch,
      });

      // Setup env (copy .env, symlink node_modules)
      await setupWorktreeEnv(projectRoot, wtPath, config);

      // Ensure tmux session
      const manifest = await readManifest(projectRoot);
      const sessionName = manifest.sessionName;
      await tmux.ensureSession(sessionName);

      // Create tmux window
      const windowTarget = await tmux.createWindow(sessionName, name, wtPath);

      // Register worktree in manifest
      const worktreeEntry: WorktreeEntry = {
        id: wtId,
        name,
        path: wtPath,
        branch: branchName,
        baseBranch,
        status: 'active',
        tmuxWindow: windowTarget,
        agents: {},
        createdAt: new Date().toISOString(),
      };

      await updateManifest(projectRoot, (m) => {
        m.worktrees[wtId] = worktreeEntry;
        return m;
      });

      // Spawn agents
      const agents: AgentEntry[] = [];
      for (let i = 0; i < count; i++) {
        const aId = genAgentId();

        // For count > 1, create additional windows
        let target = windowTarget;
        if (i > 0) {
          target = await tmux.createWindow(
            sessionName,
            `${name}-${i}`,
            wtPath,
          );
        }

        const ctx: TemplateContext = {
          WORKTREE_PATH: wtPath,
          BRANCH: branchName,
          AGENT_ID: aId,
          PROJECT_ROOT: projectRoot,
          TASK_NAME: name,
          PROMPT: promptText,
          ...userVars,
        };

        const agentEntry = await spawnAgent({
          agentId: aId,
          agentConfig,
          prompt: renderTemplate(promptText, ctx),
          worktreePath: wtPath,
          tmuxTarget: target,
          projectRoot,
          branch: branchName,
          sessionId: genSessionId(),
        });

        agents.push(agentEntry);

        await updateManifest(projectRoot, (m) => {
          if (m.worktrees[wtId]) {
            m.worktrees[wtId].agents[agentEntry.id] = agentEntry;
          }
          return m;
        });
      }

      const response: SpawnResponseBody = {
        worktreeId: wtId,
        name,
        branch: branchName,
        agents: agents.map((a) => ({
          id: a.id,
          tmuxTarget: a.tmuxTarget,
          ...(a.sessionId ? { sessionId: a.sessionId } : {}),
        })),
      };

      return reply.status(201).send(response);
    },
  );
}
