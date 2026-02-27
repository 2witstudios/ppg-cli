import type { FastifyInstance, FastifyPluginOptions } from 'fastify';
import { requireManifest, findAgent, updateManifest } from '../../core/manifest.js';
import { killAgent } from '../../core/agent.js';
import { loadConfig, resolveAgentConfig } from '../../core/config.js';
import { spawnAgent } from '../../core/agent.js';
import * as tmux from '../../core/tmux.js';
import { PpgError, AgentNotFoundError } from '../../lib/errors.js';
import { agentId as genAgentId, sessionId as genSessionId } from '../../lib/id.js';
import { agentPromptFile } from '../../lib/paths.js';
import { renderTemplate, type TemplateContext } from '../../core/template.js';
import fs from 'node:fs/promises';

export interface AgentRoutesOptions extends FastifyPluginOptions {
  projectRoot: string;
}

function mapErrorToStatus(err: unknown): number {
  if (err instanceof PpgError) {
    switch (err.code) {
      case 'AGENT_NOT_FOUND': return 404;
      case 'NOT_INITIALIZED': return 503;
      case 'MANIFEST_LOCK': return 409;
      case 'TMUX_NOT_FOUND': return 503;
      case 'INVALID_ARGS': return 400;
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
  const { projectRoot } = opts;

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
      const { id } = request.params;
      const lines = request.query.lines ? parseInt(request.query.lines, 10) : 200;

      if (isNaN(lines) || lines < 1) {
        return reply.code(400).send({ error: 'lines must be a positive integer', code: 'INVALID_ARGS' });
      }

      const manifest = await requireManifest(projectRoot);
      const found = findAgent(manifest, id);
      if (!found) throw new AgentNotFoundError(id);

      const { agent } = found;
      const content = await tmux.capturePane(agent.tmuxTarget, lines);

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
      const { id } = request.params;
      const { text, mode = 'with-enter' } = request.body;

      const manifest = await requireManifest(projectRoot);
      const found = findAgent(manifest, id);
      if (!found) throw new AgentNotFoundError(id);

      const { agent } = found;

      switch (mode) {
        case 'raw':
          await tmux.sendRawKeys(agent.tmuxTarget, text);
          break;
        case 'literal':
          await tmux.sendLiteral(agent.tmuxTarget, text);
          break;
        case 'with-enter':
        default:
          await tmux.sendKeys(agent.tmuxTarget, text);
          break;
      }

      return {
        success: true,
        agentId: agent.id,
        tmuxTarget: agent.tmuxTarget,
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
      const { id } = request.params;

      const manifest = await requireManifest(projectRoot);
      const found = findAgent(manifest, id);
      if (!found) throw new AgentNotFoundError(id);

      const { agent } = found;

      if (agent.status !== 'running') {
        return {
          success: true,
          agentId: agent.id,
          message: `Agent already ${agent.status}`,
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
      const { id } = request.params;
      const { prompt: promptOverride, agent: agentType } = request.body ?? {};

      const manifest = await requireManifest(projectRoot);
      const config = await loadConfig(projectRoot);

      const found = findAgent(manifest, id);
      if (!found) throw new AgentNotFoundError(id);

      const { worktree: wt, agent: oldAgent } = found;

      // Kill old agent if still running
      if (oldAgent.status === 'running') {
        await killAgent(oldAgent);
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

      await tmux.ensureSession(manifest.sessionName);
      const newAgentId = genAgentId();
      const windowTarget = await tmux.createWindow(manifest.sessionName, `${wt.name}-restart`, wt.path);

      // Render template vars
      const ctx: TemplateContext = {
        WORKTREE_PATH: wt.path,
        BRANCH: wt.branch,
        AGENT_ID: newAgentId,
        PROJECT_ROOT: projectRoot,
        TASK_NAME: wt.name,
        PROMPT: promptText,
      };
      const renderedPrompt = renderTemplate(promptText, ctx);

      const newSessionId = genSessionId();
      const agentEntry = await spawnAgent({
        agentId: newAgentId,
        agentConfig,
        prompt: renderedPrompt,
        worktreePath: wt.path,
        tmuxTarget: windowTarget,
        projectRoot,
        branch: wt.branch,
        sessionId: newSessionId,
      });

      // Update manifest: mark old agent as gone, add new agent
      await updateManifest(projectRoot, (m) => {
        const mWt = m.worktrees[wt.id];
        if (mWt) {
          const mOldAgent = mWt.agents[oldAgent.id];
          if (mOldAgent && mOldAgent.status === 'running') {
            mOldAgent.status = 'gone';
          }
          mWt.agents[newAgentId] = agentEntry;
        }
        return m;
      });

      return {
        success: true,
        oldAgentId: oldAgent.id,
        newAgent: {
          id: newAgentId,
          tmuxTarget: windowTarget,
          sessionId: newSessionId,
          worktreeId: wt.id,
          worktreeName: wt.name,
          branch: wt.branch,
          path: wt.path,
        },
      };
    } catch (err) {
      const status = mapErrorToStatus(err);
      return reply.code(status).send(errorPayload(err));
    }
  });
}
