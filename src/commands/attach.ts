import { requireManifest, resolveWorktree, findAgent } from '../core/manifest.js';
import { getRepoRoot } from '../core/worktree.js';
import { getPaneInfo } from '../core/tmux.js';
import { resumeAgent } from '../core/agent.js';
import * as tmux from '../core/tmux.js';
import { openTerminalWindow } from '../core/terminal.js';
import { PoguError } from '../lib/errors.js';
import { info, success } from '../lib/output.js';
import type { AgentEntry } from '../types/manifest.js';

export async function attachCommand(target: string): Promise<void> {
  const projectRoot = await getRepoRoot();

  const manifest = await requireManifest(projectRoot);

  // Try to resolve target as worktree ID, worktree name, or agent ID
  let tmuxTarget: string | undefined;
  const sessionName = manifest.sessionName;
  let agent: AgentEntry | undefined;
  let worktreeId: string | undefined;

  // Check worktree ID
  const wt = resolveWorktree(manifest, target);

  if (wt) {
    if (!wt.tmuxWindow) {
      throw new PoguError('Worktree has no tmux window. Spawn agents first with: pogu spawn --worktree ' + wt.id + ' --prompt "your task"', 'NO_TMUX_WINDOW');
    }
    tmuxTarget = wt.tmuxWindow;
  } else {
    // Check agent ID
    const found = findAgent(manifest, target);
    if (found) {
      agent = found.agent;
      worktreeId = found.worktree.id;
      tmuxTarget = found.agent.tmuxTarget;
    }
  }

  if (!tmuxTarget) {
    throw new PoguError(`Could not resolve target: ${target}. Try a worktree ID, name, or agent ID.`, 'TARGET_NOT_FOUND');
  }

  // Check if the pane is dead and agent has a sessionId — auto-resume
  if (agent?.sessionId && worktreeId) {
    const paneInfo = await getPaneInfo(tmuxTarget);
    if (!paneInfo || paneInfo.isDead) {
      info(`Pane is dead. Resuming session ${agent.sessionId}...`);
      const resumeWt = manifest.worktrees[worktreeId];
      const cwd = resumeWt?.path ?? projectRoot;
      const windowName = resumeWt?.name ?? agent.name ?? target;

      tmuxTarget = await resumeAgent({
        agent,
        worktreeId,
        sessionName,
        cwd,
        windowName,
        projectRoot,
      });
      success(`Resumed agent ${agent.id} in ${tmuxTarget}`);
    }
  }

  const insideTmux = await tmux.isInsideTmux();

  if (insideTmux) {
    // Agent targets are now window targets (e.g. "pogu:3"), so use selectWindow for both
    await tmux.selectWindow(tmuxTarget);
    info(`Switched to ${tmuxTarget}`);
  } else {
    // Open a new Terminal.app window attached to the target
    const title = wt ? wt.name : target;
    info(`Opening Terminal window for ${title}`);
    await openTerminalWindow(sessionName, tmuxTarget, title);
  }
}
