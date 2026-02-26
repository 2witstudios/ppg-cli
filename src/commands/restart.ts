import fs from 'node:fs/promises';
import { requireManifest, updateManifest, findAgent } from '../core/manifest.js';
import { loadConfig, resolveAgentConfig } from '../core/config.js';
import { spawnAgent, killAgent } from '../core/agent.js';
import { getRepoRoot } from '../core/worktree.js';
import * as tmux from '../core/tmux.js';
import { openTerminalWindow } from '../core/terminal.js';
import { agentId as genAgentId, sessionId as genSessionId } from '../lib/id.js';
import { agentPromptFile, resultFile } from '../lib/paths.js';
import { PpgError, AgentNotFoundError } from '../lib/errors.js';
import { output, success, info } from '../lib/output.js';
import { renderTemplate, type TemplateContext } from '../core/template.js';

export interface RestartOptions {
  prompt?: string;
  agent?: string;
  open?: boolean;
  json?: boolean;
}

export async function restartCommand(agentRef: string, options: RestartOptions): Promise<void> {
  const projectRoot = await getRepoRoot();
  const config = await loadConfig(projectRoot);

  const manifest = await requireManifest(projectRoot);

  const found = findAgent(manifest, agentRef);
  if (!found) throw new AgentNotFoundError(agentRef);

  const { worktree: wt, agent: oldAgent } = found;

  // Kill old agent if still running
  if (['running', 'spawning', 'waiting'].includes(oldAgent.status)) {
    info(`Killing existing agent ${oldAgent.id}`);
    await killAgent(oldAgent);
  }

  // Read original prompt from prompt file, or use override
  let promptText: string;
  if (options.prompt) {
    promptText = options.prompt;
  } else {
    const pFile = agentPromptFile(projectRoot, oldAgent.id);
    try {
      promptText = await fs.readFile(pFile, 'utf-8');
    } catch {
      throw new PpgError(
        `Could not read original prompt for agent ${oldAgent.id}. Use --prompt to provide one.`,
        'PROMPT_NOT_FOUND',
      );
    }
  }

  // Resolve agent config
  const agentConfig = resolveAgentConfig(config, options.agent ?? oldAgent.agentType);

  // Ensure tmux session
  await tmux.ensureSession(manifest.sessionName);

  // Create new tmux window in same worktree
  const newAgentId = genAgentId();
  const windowTarget = await tmux.createWindow(manifest.sessionName, `${wt.name}-restart`, wt.path);

  // Render template vars
  const ctx: TemplateContext = {
    WORKTREE_PATH: wt.path,
    BRANCH: wt.branch,
    AGENT_ID: newAgentId,
    RESULT_FILE: resultFile(projectRoot, newAgentId),
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
    skipResultInstructions: !options.prompt,
  });

  // Update manifest: mark old agent as killed, add new agent
  await updateManifest(projectRoot, (m) => {
    const mWt = m.worktrees[wt.id];
    if (mWt) {
      const mOldAgent = mWt.agents[oldAgent.id];
      if (mOldAgent && !['completed', 'failed', 'killed', 'lost'].includes(mOldAgent.status)) {
        mOldAgent.status = 'killed';
        mOldAgent.completedAt = new Date().toISOString();
      }
      mWt.agents[newAgentId] = agentEntry;
    }
    return m;
  });

  // Only open Terminal window when explicitly requested via --open (fire-and-forget)
  if (options.open === true) {
    openTerminalWindow(manifest.sessionName, windowTarget, `${wt.name}-restart`).catch(() => {});
  }

  if (options.json) {
    output({
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
    }, true);
  } else {
    success(`Restarted agent ${oldAgent.id} → ${newAgentId} in worktree ${wt.name}`);
    info(`  New agent ${newAgentId} → ${windowTarget}`);
  }
}
