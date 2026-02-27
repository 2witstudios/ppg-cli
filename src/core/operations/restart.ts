import fs from 'node:fs/promises';
import { requireManifest, updateManifest, findAgent } from '../manifest.js';
import { loadConfig, resolveAgentConfig } from '../config.js';
import { spawnAgent, killAgent } from '../agent.js';
import { getRepoRoot } from '../worktree.js';
import { getBackend } from '../backend.js';
import { agentId as genAgentId, sessionId as genSessionId } from '../../lib/id.js';
import { agentPromptFile } from '../../lib/paths.js';
import { AgentNotFoundError, PromptNotFoundError } from '../../lib/errors.js';
import { renderTemplate, type TemplateContext } from '../template.js';

export interface RestartParams {
  agentRef: string;
  prompt?: string;
  agentType?: string;
  projectRoot?: string;
}

export interface RestartResult {
  oldAgentId: string;
  killedOldAgent: boolean;
  newAgent: {
    id: string;
    tmuxTarget: string;
    sessionId: string;
    worktreeId: string;
    worktreeName: string;
    branch: string;
    path: string;
  };
  sessionName: string;
}

export async function performRestart(params: RestartParams): Promise<RestartResult> {
  const { agentRef, prompt: promptOverride, agentType } = params;

  const projectRoot = params.projectRoot ?? await getRepoRoot();
  const config = await loadConfig(projectRoot);
  const manifest = await requireManifest(projectRoot);

  const found = findAgent(manifest, agentRef);
  if (!found) throw new AgentNotFoundError(agentRef);

  const { worktree: wt, agent: oldAgent } = found;

  // Kill old agent if still running
  let killedOldAgent = false;
  if (oldAgent.status === 'running') {
    await killAgent(oldAgent);
    killedOldAgent = true;
  }

  // Read original prompt from prompt file, or use override
  let promptText: string;
  if (promptOverride) {
    promptText = promptOverride;
  } else {
    const pFile = agentPromptFile(projectRoot, oldAgent.id);
    try {
      promptText = await fs.readFile(pFile, 'utf-8');
    } catch {
      throw new PromptNotFoundError(oldAgent.id);
    }
  }

  // Resolve agent config
  const agentConfig = resolveAgentConfig(config, agentType ?? oldAgent.agentType);

  // Ensure tmux session
  await getBackend().ensureSession(manifest.sessionName);

  // Create new tmux window in same worktree
  const newAgentId = genAgentId();
  const windowTarget = await getBackend().createWindow(manifest.sessionName, `${wt.name}-restart`, wt.path);

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
    oldAgentId: oldAgent.id,
    killedOldAgent,
    newAgent: {
      id: newAgentId,
      tmuxTarget: windowTarget,
      sessionId: newSessionId,
      worktreeId: wt.id,
      worktreeName: wt.name,
      branch: wt.branch,
      path: wt.path,
    },
    sessionName: manifest.sessionName,
  };
}
