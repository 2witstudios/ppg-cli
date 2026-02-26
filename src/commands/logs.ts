import { requireManifest, findAgent } from '../core/manifest.js';
import { getRepoRoot } from '../core/worktree.js';
import * as tmux from '../core/tmux.js';
import { PgError, AgentNotFoundError } from '../lib/errors.js';
import { output, outputError } from '../lib/output.js';

export interface LogsOptions {
  lines?: number;
  follow?: boolean;
  full?: boolean;
  json?: boolean;
}

export async function logsCommand(agentId: string, options: LogsOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  const manifest = await requireManifest(projectRoot);

  const found = findAgent(manifest, agentId);
  if (!found) throw new AgentNotFoundError(agentId);

  const { agent } = found;
  const lines = options.full ? undefined : (options.lines ?? 100);

  if (options.follow) {
    // Poll mode
    let lastOutput = '';
    const interval = setInterval(async () => {
      try {
        const content = await tmux.capturePane(agent.tmuxTarget, lines);
        if (content !== lastOutput) {
          // Find new lines
          if (lastOutput) {
            const oldLines = lastOutput.split('\n');
            const newLines = content.split('\n');
            // Output only lines that are new
            const diff = newLines.slice(oldLines.length);
            if (diff.length > 0) {
              process.stdout.write(diff.join('\n') + '\n');
            }
          } else {
            process.stdout.write(content + '\n');
          }
          lastOutput = content;
        }
      } catch {
        clearInterval(interval);
        outputError(new Error('Pane no longer available'), options.json ?? false);
        process.exit(1);
      }
    }, 1000);

    process.on('SIGINT', () => {
      clearInterval(interval);
      process.exit(0);
    });
  } else {
    // One-shot capture
    try {
      const content = await tmux.capturePane(agent.tmuxTarget, lines);
      if (options.json) {
        output({
          agentId: agent.id,
          status: agent.status,
          tmuxTarget: agent.tmuxTarget,
          output: content,
        }, true);
      } else {
        console.log(content);
      }
    } catch {
      throw new PgError(`Could not capture pane for agent ${agentId}. Pane may no longer exist.`, 'PANE_NOT_FOUND');
    }
  }
}
