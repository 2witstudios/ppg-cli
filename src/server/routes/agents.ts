import type { FastifyInstance, FastifyPluginOptions, FastifyRequest } from 'fastify';
import { requireManifest, readManifest, findAgent, updateManifest } from '../../core/manifest.js';
import { killAgent, checkAgentStatus, restartAgent, spawnMasterAgent } from '../../core/agent.js';
import { loadConfig, resolveAgentConfig } from '../../core/config.js';
import * as tmux from '../../core/tmux.js';
import { PpgError, AgentNotFoundError } from '../../lib/errors.js';
import { agentPromptFile } from '../../lib/paths.js';
import fs from 'node:fs/promises';

export interface AgentRoutesOptions extends FastifyPluginOptions {
  projectRoot: string;
}

const MAX_LINES = 10_000;

function mapErrorToStatus(err: unknown): number {
  if (err instanceof PpgError) {
    switch (err.code) {
      case 'AGENT_NOT_FOUND': return 404;
      case 'PANE_NOT_FOUND': return 410;
      case 'NOT_INITIALIZED': return 503;
      case 'MANIFEST_LOCK': return 409;
      case 'TMUX_NOT_FOUND': return 503;
      case 'INVALID_ARGS': return 400;
      case 'PROMPT_NOT_FOUND': return 400;
      default: return 500;
    }
  }
  return 500;
}

function errorPayload(err: unknown): { error: string; code?: string } {
  if (err instanceof PpgError) {
    return { error: err.message, code: err.code };
  }
  return { error: err instanceof Error ? err.message : String(err) };
}

export async function agentRoutes(
  app: FastifyInstance,
  opts: AgentRoutesOptions,
): Promise<void> {
  const resolveRoot = async (request: FastifyRequest): Promise<string> => {
    const getter = (app as any).getProjectRoot as
      | ((req: FastifyRequest) => Promise<string>)
      | undefined;
    if (getter) {
      try { return await getter(request); } catch { /* fall through */ }
    }
    return opts.projectRoot;
  };

  // ---------- GET /api/agents/:id/logs ----------
  app.get<{
    Params: { id: string };
    Querystring: { lines?: string };
  }>('/agents/:id/logs', {
    schema: {
      params: {
        type: 'object',
        required: ['id'],
        properties: { id: { type: 'string' } },
      },
      querystring: {
        type: 'object',
        properties: { lines: { type: 'string' } },
      },
    },
  }, async (request, reply) => {
    try {
      const projectRoot = await resolveRoot(request);
      const { id } = request.params;
      const lines = request.query.lines
        ? Math.min(parseInt(request.query.lines, 10), MAX_LINES)
        : 200;

      if (isNaN(lines) || lines < 1) {
        return reply.code(400).send({ error: 'lines must be a positive integer', code: 'INVALID_ARGS' });
      }

      const manifest = await requireManifest(projectRoot);
      const found = findAgent(manifest, id);

      // If not found in manifest and id looks like a tmux target, treat as untracked window
      if (!found && id.includes(':')) {
        let content: string;
        try {
          content = await tmux.capturePane(id, lines);
        } catch {
          throw new PpgError(
            `Could not capture pane for target ${id}. Pane may no longer exist.`,
            'PANE_NOT_FOUND',
          );
        }
        return {
          agentId: id,
          tmuxTarget: id,
          lines,
          output: content,
        };
      }

      if (!found) throw new AgentNotFoundError(id);

      const { agent } = found;

      let content: string;
      try {
        content = await tmux.capturePane(agent.tmuxTarget, lines);
      } catch {
        throw new PpgError(
          `Could not capture pane for agent ${id}. Pane may no longer exist.`,
          'PANE_NOT_FOUND',
        );
      }

      return {
        agentId: agent.id,
        status: agent.status,
        tmuxTarget: agent.tmuxTarget,
        lines,
        output: content,
      };
    } catch (err) {
      const status = mapErrorToStatus(err);
      return reply.code(status).send(errorPayload(err));
    }
  });

  // ---------- POST /api/agents/:id/send ----------
  app.post<{
    Params: { id: string };
    Body: { text: string; mode?: 'raw' | 'literal' | 'with-enter' };
  }>('/agents/:id/send', {
    schema: {
      params: {
        type: 'object',
        required: ['id'],
        properties: { id: { type: 'string' } },
      },
      body: {
        type: 'object',
        required: ['text'],
        properties: {
          text: { type: 'string' },
          mode: { type: 'string', enum: ['raw', 'literal', 'with-enter'] },
        },
      },
    },
  }, async (request, reply) => {
    try {
      const projectRoot = await resolveRoot(request);
      const { id } = request.params;
      const { text, mode = 'with-enter' } = request.body;

      const manifest = await requireManifest(projectRoot);
      const found = findAgent(manifest, id);

      // Resolve tmux target — use id directly if it looks like a tmux target (untracked window)
      const tmuxTarget = found ? found.agent.tmuxTarget : (id.includes(':') ? id : null);
      if (!tmuxTarget) throw new AgentNotFoundError(id);

      switch (mode) {
        case 'raw':
          await tmux.sendRawKeys(tmuxTarget, text);
          break;
        case 'literal':
          await tmux.sendLiteral(tmuxTarget, text);
          break;
        case 'with-enter':
        default:
          await tmux.sendKeys(tmuxTarget, text);
          break;
      }

      return {
        success: true,
        agentId: found ? found.agent.id : id,
        tmuxTarget,
        text,
        mode,
      };
    } catch (err) {
      const status = mapErrorToStatus(err);
      return reply.code(status).send(errorPayload(err));
    }
  });

  // ---------- POST /api/agents/:id/kill ----------
  app.post<{
    Params: { id: string };
  }>('/agents/:id/kill', {
    schema: {
      params: {
        type: 'object',
        required: ['id'],
        properties: { id: { type: 'string' } },
      },
    },
  }, async (request, reply) => {
    try {
      const projectRoot = await resolveRoot(request);
      const { id } = request.params;

      const manifest = await requireManifest(projectRoot);
      const found = findAgent(manifest, id);
      if (!found) throw new AgentNotFoundError(id);

      const { agent } = found;

      // Refresh live status from tmux (manifest may be stale in long-lived server)
      const { status: liveStatus } = await checkAgentStatus(agent, projectRoot);

      if (liveStatus !== 'running') {
        return {
          success: true,
          agentId: agent.id,
          message: `Agent already ${liveStatus}`,
        };
      }

      await killAgent(agent);

      await updateManifest(projectRoot, (m) => {
        const f = findAgent(m, id);
        if (f) {
          f.agent.status = 'gone';
        }
        return m;
      });

      return {
        success: true,
        agentId: agent.id,
        killed: true,
      };
    } catch (err) {
      const status = mapErrorToStatus(err);
      return reply.code(status).send(errorPayload(err));
    }
  });

  // ---------- GET /api/agents ----------
  app.get('/agents', async (request, reply) => {
    try {
      const projectRoot = await resolveRoot(request);
      const manifest = await requireManifest(projectRoot);
      const allAgents: Array<{ id: string; name: string; agentType: string; status: string; master: boolean; worktreeId?: string }> = [];

      // Master agents
      for (const agent of Object.values(manifest.agents ?? {})) {
        allAgents.push({ ...agent, master: true });
      }

      // Worktree agents
      for (const wt of Object.values(manifest.worktrees)) {
        for (const agent of Object.values(wt.agents)) {
          allAgents.push({ ...agent, master: false, worktreeId: wt.id });
        }
      }

      return { agents: allAgents };
    } catch (err) {
      const status = mapErrorToStatus(err);
      return reply.code(status).send(errorPayload(err));
    }
  });

  // ---------- POST /api/agents/master ----------
  app.post<{
    Body: { name?: string; agent?: string; prompt: string };
  }>('/agents/master', {
    schema: {
      body: {
        type: 'object',
        required: ['prompt'],
        properties: {
          name: { type: 'string' },
          agent: { type: 'string' },
          prompt: { type: 'string' },
        },
      },
    },
  }, async (request, reply) => {
    try {
      const projectRoot = await resolveRoot(request);
      const { name = 'master', agent: agentType, prompt } = request.body;
      const manifest = await readManifest(projectRoot);
      const config = await loadConfig(projectRoot);
      const agentConfig = resolveAgentConfig(config, agentType);

      const result = await spawnMasterAgent({
        projectRoot,
        name,
        agentType: agentConfig.name,
        prompt,
        agentConfig,
        sessionName: manifest.sessionName,
      });

      return {
        success: true,
        agent: result,
      };
    } catch (err) {
      const status = mapErrorToStatus(err);
      return reply.code(status).send(errorPayload(err));
    }
  });

  // ---------- POST /api/agents/:id/restart ----------
  app.post<{
    Params: { id: string };
    Body: { prompt?: string; agent?: string };
  }>('/agents/:id/restart', {
    schema: {
      params: {
        type: 'object',
        required: ['id'],
        properties: { id: { type: 'string' } },
      },
      body: {
        type: 'object',
        properties: {
          prompt: { type: 'string' },
          agent: { type: 'string' },
        },
      },
    },
  }, async (request, reply) => {
    try {
      const projectRoot = await resolveRoot(request);
      const { id } = request.params;
      const { prompt: promptOverride, agent: agentType } = request.body ?? {};

      const manifest = await requireManifest(projectRoot);
      const config = await loadConfig(projectRoot);

      const found = findAgent(manifest, id);
      if (!found) throw new AgentNotFoundError(id);

      const { worktree: wt, agent: oldAgent } = found;

      if (!wt) {
        throw new PpgError('Master agents cannot be restarted via this endpoint', 'INVALID_ARGS');
      }

      // Read original prompt or use override
      let promptText: string;
      if (promptOverride) {
        promptText = promptOverride;
      } else {
        const pFile = agentPromptFile(projectRoot, oldAgent.id);
        try {
          promptText = await fs.readFile(pFile, 'utf-8');
        } catch {
          throw new PpgError(
            `Could not read original prompt for agent ${oldAgent.id}. Provide a prompt in the request body.`,
            'PROMPT_NOT_FOUND',
          );
        }
      }

      const agentConfig = resolveAgentConfig(config, agentType ?? oldAgent.agentType);

      const result = await restartAgent({
        projectRoot,
        agentId: oldAgent.id,
        worktree: wt,
        oldAgent,
        sessionName: manifest.sessionName,
        agentConfig,
        promptText,
      });

      return {
        success: true,
        oldAgentId: result.oldAgentId,
        newAgent: {
          id: result.newAgentId,
          tmuxTarget: result.tmuxTarget,
          sessionId: result.sessionId,
          worktreeId: result.worktreeId,
          worktreeName: result.worktreeName,
          branch: result.branch,
          path: result.path,
        },
      };
    } catch (err) {
      const status = mapErrorToStatus(err);
      return reply.code(status).send(errorPayload(err));
    }
  });
}
