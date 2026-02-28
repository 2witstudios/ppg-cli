import { performSpawn, type PerformSpawnOptions, type SpawnResult } from '../core/operations/spawn.js';
import { output, success, info } from '../lib/output.js';

export interface SpawnOptions extends PerformSpawnOptions {
  master?: boolean;
  json?: boolean;
}

export async function spawnCommand(options: SpawnOptions): Promise<void> {
  if (options.master) {
    return spawnMasterCommand(options);
  }

  const { json, master, ...spawnOpts } = options;

  const result = await performSpawn(spawnOpts);

  emitSpawnResult(result, options);
}

async function spawnMasterCommand(options: SpawnOptions): Promise<void> {
  const { getRepoRoot } = await import('../core/worktree.js');
  const { loadConfig, resolveAgentConfig } = await import('../core/config.js');
  const { readManifest } = await import('../core/manifest.js');
  const { spawnMasterAgent } = await import('../core/agent.js');

  const projectRoot = await getRepoRoot();
  const config = await loadConfig(projectRoot);
  const manifest = await readManifest(projectRoot);
  const agentConfig = resolveAgentConfig(config, options.agent);

  if (!options.prompt) {
    throw new (await import('../lib/errors.js')).PpgError(
      '--prompt is required for --master agents',
      'INVALID_ARGS',
    );
  }

  const name = options.name ?? 'master';
  const result = await spawnMasterAgent({
    projectRoot,
    name,
    agentType: agentConfig.name,
    prompt: options.prompt,
    agentConfig,
    sessionName: manifest.sessionName,
  });

  if (options.json) {
    output({
      success: true,
      master: true,
      agent: result,
    }, true);
  } else {
    success(`Spawned master agent ${result.agentId}`);
    info(`  tmux: ${result.tmuxTarget}`);
  }
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
