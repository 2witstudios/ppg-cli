import { performSpawn, type PerformSpawnOptions, type SpawnResult } from '../core/operations/spawn.js';
import { output, success, info } from '../lib/output.js';

export interface SpawnOptions extends PerformSpawnOptions {
  json?: boolean;
}

export async function spawnCommand(options: SpawnOptions): Promise<void> {
  const { json, ...spawnOpts } = options;

  const result = await performSpawn(spawnOpts);

  emitSpawnResult(result, options);
}

function emitSpawnResult(result: SpawnResult, options: SpawnOptions): void {
  if (options.json) {
    output({
      success: true,
      worktree: result.worktree,
      agents: result.agents,
    }, true);
    return;
  }

  const agentCount = result.agents.length;

  if (options.worktree) {
    success(`Added ${agentCount} agent(s) to worktree ${result.worktree.id}`);
  } else if (options.branch) {
    success(`Spawned worktree ${result.worktree.id} from branch ${options.branch} with ${agentCount} agent(s)`);
  } else {
    success(`Spawned worktree ${result.worktree.id} with ${agentCount} agent(s)`);
  }

  for (const a of result.agents) {
    info(`  Agent ${a.id} → ${a.tmuxTarget}`);
  }

  // Only show attach hint for newly created worktrees, not when adding to existing
  if (!options.worktree) {
    info(`Attach: ppg attach ${result.worktree.id}`);
  }
}
