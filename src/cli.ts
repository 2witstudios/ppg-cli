import { Command } from 'commander';
import { PgError } from './lib/errors.js';
import { outputError } from './lib/output.js';

const program = new Command();

program
  .name('ppg')
  .description('Pure Point Guard — local orchestration runtime for parallel CLI coding agents')
  .version('0.1.0');

program
  .command('init')
  .description('Initialize Point Guard in the current git repository')
  .option('--json', 'Output as JSON')
  .action(async (options) => {
    const { initCommand } = await import('./commands/init.js');
    await initCommand(options);
  });

program
  .command('spawn')
  .description('Spawn a new worktree and agent(s), or add agents to an existing worktree')
  .option('-n, --name <name>', 'Name for the worktree/task')
  .option('-a, --agent <type>', 'Agent type to use (default: claude)')
  .option('-p, --prompt <text>', 'Prompt text for the agent')
  .option('-f, --prompt-file <path>', 'File containing the prompt')
  .option('-t, --template <name>', 'Template name from .pg/templates/')
  .option('--var <key=value...>', 'Template variables', collectVars, [])
  .option('-b, --base <branch>', 'Base branch for the worktree')
  .option('-w, --worktree <id>', 'Add agent to existing worktree')
  .option('-c, --count <n>', 'Number of agents to spawn', parseInt, 1)
  .option('--no-open', 'Do not open a Terminal window for the spawned agents')
  .option('--json', 'Output as JSON')
  .action(async (options) => {
    const { spawnCommand } = await import('./commands/spawn.js');
    await spawnCommand(options);
  });

program
  .command('status')
  .description('Show status of worktrees and agents')
  .argument('[worktree]', 'Filter by worktree ID or name')
  .option('--json', 'Output as JSON')
  .option('-w, --watch', 'Watch for status changes')
  .action(async (worktree, options) => {
    const { statusCommand } = await import('./commands/status.js');
    await statusCommand(worktree, options);
  });

program
  .command('kill')
  .description('Kill agents or worktrees')
  .option('-a, --agent <id>', 'Kill a specific agent')
  .option('-w, --worktree <id>', 'Kill all agents in a worktree')
  .option('--all', 'Kill all agents in all worktrees')
  .option('-r, --remove', 'Also remove the worktree after killing')
  .option('--json', 'Output as JSON')
  .action(async (options) => {
    const { killCommand } = await import('./commands/kill.js');
    await killCommand(options);
  });

program
  .command('attach')
  .description('Attach to a worktree or agent tmux pane')
  .argument('<target>', 'Worktree ID, agent ID, or name')
  .action(async (target) => {
    const { attachCommand } = await import('./commands/attach.js');
    await attachCommand(target);
  });

program
  .command('logs')
  .description('View agent pane output')
  .argument('<agent-id>', 'Agent ID')
  .option('-l, --lines <n>', 'Number of lines to show', parseInt, 100)
  .option('-f, --follow', 'Follow output (poll every 1s)')
  .option('--full', 'Show full pane history')
  .option('--json', 'Output as JSON')
  .action(async (agentId, options) => {
    const { logsCommand } = await import('./commands/logs.js');
    await logsCommand(agentId, options);
  });

program
  .command('aggregate')
  .description('Aggregate results from completed agents')
  .argument('[worktree-id]', 'Worktree ID to aggregate results from')
  .option('--all', 'Aggregate from all worktrees')
  .option('-o, --output <file>', 'Write output to file')
  .option('--json', 'Output as JSON')
  .action(async (worktreeId, options) => {
    const { aggregateCommand } = await import('./commands/aggregate.js');
    await aggregateCommand(worktreeId, options);
  });

program
  .command('merge')
  .description('Merge a worktree branch back into base')
  .argument('<worktree-id>', 'Worktree ID to merge')
  .option('-s, --strategy <strategy>', 'Merge strategy: squash or no-ff', 'squash')
  .option('--no-cleanup', 'Do not remove worktree after merge')
  .option('--dry-run', 'Show what would be done without doing it')
  .option('--force', 'Merge even if agents are not completed')
  .option('--json', 'Output as JSON')
  .action(async (worktreeId, options) => {
    const { mergeCommand } = await import('./commands/merge.js');
    await mergeCommand(worktreeId, options);
  });

program
  .command('list')
  .description('List available templates')
  .argument('<type>', 'What to list: templates')
  .option('--json', 'Output as JSON')
  .action(async (type, options) => {
    const { listCommand } = await import('./commands/list.js');
    await listCommand(type, options);
  });

// Error handling
program.exitOverride();

function collectVars(value: string, previous: string[]): string[] {
  return previous.concat([value]);
}

async function main() {
  try {
    await program.parseAsync(process.argv);
  } catch (err) {
    if (err instanceof PgError) {
      outputError(err, program.opts().json ?? false);
      process.exit(err.exitCode);
    }
    if (err instanceof Error && 'code' in err) {
      const code = (err as { code: string }).code;
      if (code === 'commander.helpDisplayed' || code === 'commander.version') {
        process.exit(0);
      }
    }
    outputError(err, false);
    process.exit(1);
  }
}

main();
