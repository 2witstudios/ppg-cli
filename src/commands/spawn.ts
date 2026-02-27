import { performSpawn, type PerformSpawnOptions, type SpawnResult } from '../core/operations/spawn.js';
import { output, success, info } from '../lib/output.js';

export interface SpawnOptions extends PerformSpawnOptions {
  json?: boolean;
}

export async function spawnCommand(options: SpawnOptions): Promise<void> {
  const { json, ...spawnOpts } = options;

  const result = await performSpawn(spawnOpts);

  emitSpawnResult(result, json);
}

function emitSpawnResult(result: SpawnResult, json: boolean | undefined): void {
  if (json) {
    output({
      success: true,
      worktree: result.worktree,
      agents: result.agents,
    }, true);
    return;
  }

  const agentCount = result.agents.length;
  success(`Spawned worktree ${result.worktree.id} with ${agentCount} agent(s)`);
  for (const a of result.agents) {
    info(`  Agent ${a.id} → ${a.tmuxTarget}`);
  }
  info(`Attach: ppg attach ${result.worktree.id}`);
}
