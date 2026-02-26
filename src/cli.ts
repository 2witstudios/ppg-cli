import { createRequire } from 'node:module';
import { Command } from 'commander';
import { PpgError } from './lib/errors.js';
import { outputError } from './lib/output.js';

const require = createRequire(import.meta.url);
const pkg = require('../package.json') as { version: string };

const program = new Command();

program
  .name('ppg')
  .description('Pure Point Guard — local orchestration runtime for parallel CLI coding agents')
  .version(pkg.version)
  .option('--json', 'Output as JSON');

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
  .option('-t, --template <name>', 'Template name from .ppg/templates/')
  .option('--var <key=value...>', 'Template variables', collectVars, [])
  .option('-b, --base <branch>', 'Base branch for the worktree')
  .option('-w, --worktree <id>', 'Add agent to existing worktree')
  .option('-c, --count <n>', 'Number of agents to spawn', parsePositiveInt('count'), 1)
  .option('--split', 'Put all agents in one window as split panes')
  .option('--open', 'Open a Terminal window for the spawned agents')
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
  .option('-d, --delete', 'Delete agent/worktree entry from manifest after killing')
  .option('--include-open-prs', 'Include worktrees with open GitHub PRs in deletion')
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
  .option('-l, --lines <n>', 'Number of lines to show', (v: string) => Number(v), 100)
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
  .command('swarm')
  .description('Run a swarm template — spawn multiple agents from a predefined workflow')
  .argument('<template>', 'Swarm template name from .ppg/swarms/')
  .option('-w, --worktree <ref>', 'Target an existing worktree by ID, name, or branch')
  .option('--var <key=value...>', 'Template variables', collectVars, [])
  .option('-n, --name <name>', 'Override worktree name')
  .option('-b, --base <branch>', 'Base branch for new worktree(s)')
  .option('--open', 'Open Terminal windows for spawned agents')
  .option('--json', 'Output as JSON')
  .action(async (template, options) => {
    const { swarmCommand } = await import('./commands/swarm.js');
    await swarmCommand(template, options);
  });

program
  .command('prompt')
  .description('Spawn a worktree+agent using a named prompt from .ppg/prompts/')
  .argument('<name>', 'Prompt name (filename without .md)')
  .option('-n, --name <name>', 'Name for the worktree')
  .option('-a, --agent <type>', 'Agent type to use (default: claude)')
  .option('--var <key=value...>', 'Template variables', collectVars, [])
  .option('-b, --base <branch>', 'Base branch for the worktree')
  .option('-c, --count <n>', 'Number of agents to spawn', parsePositiveInt('count'), 1)
  .option('--split', 'Put all agents in one window as split panes')
  .option('--open', 'Open a Terminal window for the spawned agents')
  .option('--json', 'Output as JSON')
  .action(async (name, options) => {
    const { promptCommand } = await import('./commands/prompt.js');
    await promptCommand(name, options);
  });

program
  .command('list')
  .description('List available templates, swarms, or prompts')
  .argument('<type>', 'What to list: templates, swarms, prompts')
  .option('--json', 'Output as JSON')
  .action(async (type, options) => {
    const { listCommand } = await import('./commands/list.js');
    await listCommand(type, options);
  });

program
  .command('restart')
  .description('Restart a failed/killed agent in the same worktree')
  .argument('<agent-id>', 'Agent ID to restart')
  .option('-p, --prompt <text>', 'Override the original prompt')
  .option('-a, --agent <type>', 'Override the agent type')
  .option('--open', 'Open a Terminal window for the restarted agent')
  .option('--json', 'Output as JSON')
  .action(async (agentId, options) => {
    const { restartCommand } = await import('./commands/restart.js');
    await restartCommand(agentId, options);
  });

program
  .command('diff')
  .description('Show changes made in a worktree branch')
  .argument('<worktree-id>', 'Worktree ID or name')
  .option('--stat', 'Show diffstat summary')
  .option('--name-only', 'Show only changed file names')
  .option('--json', 'Output as JSON')
  .action(async (worktreeId, options) => {
    const { diffCommand } = await import('./commands/diff.js');
    await diffCommand(worktreeId, options);
  });

program
  .command('pr')
  .description('Create a GitHub PR from a worktree branch')
  .argument('<worktree-id>', 'Worktree ID or name')
  .option('--title <text>', 'PR title (default: worktree name)')
  .option('--body <text>', 'PR body (default: agent result content)')
  .option('--draft', 'Create as draft PR')
  .option('--json', 'Output as JSON')
  .action(async (worktreeId, options) => {
    const { prCommand } = await import('./commands/pr.js');
    await prCommand(worktreeId, options);
  });

program
  .command('reset')
  .description('Kill all agents, remove all worktrees, and wipe manifest')
  .option('--force', 'Reset even if worktrees have unmerged/un-PR\'d work')
  .option('--prune', 'Also run git worktree prune')
  .option('--include-open-prs', 'Include worktrees with open GitHub PRs in cleanup')
  .option('--json', 'Output as JSON')
  .action(async (options) => {
    const { resetCommand } = await import('./commands/reset.js');
    await resetCommand(options);
  });

program
  .command('clean')
  .description('Remove worktrees in terminal states (merged/cleaned/failed)')
  .option('--all', 'Also clean failed worktrees')
  .option('--dry-run', 'Show what would be done without doing it')
  .option('--prune', 'Also run git worktree prune')
  .option('--include-open-prs', 'Include worktrees with open GitHub PRs in cleanup')
  .option('--json', 'Output as JSON')
  .action(async (options) => {
    const { cleanCommand } = await import('./commands/clean.js');
    await cleanCommand(options);
  });

program
  .command('send')
  .description('Send text to an agent\'s tmux pane')
  .argument('<agent-id>', 'Agent ID')
  .argument('<text>', 'Text to send')
  .option('--keys', 'Send raw tmux key names (e.g., C-c, Enter)')
  .option('--no-enter', 'Do not append Enter after the text')
  .option('--json', 'Output as JSON')
  .action(async (agentId, text, options) => {
    const { sendCommand } = await import('./commands/send.js');
    await sendCommand(agentId, text, options);
  });

program
  .command('wait')
  .description('Wait for agents to reach terminal state')
  .argument('[worktree-id]', 'Worktree ID or name')
  .option('--all', 'Wait for all agents across all worktrees')
  .option('--timeout <seconds>', 'Timeout in seconds', parsePositiveInt('timeout'))
  .option('--interval <seconds>', 'Poll interval in seconds', parsePositiveInt('interval'))
  .option('--json', 'Output as JSON')
  .action(async (worktreeId, options) => {
    const { waitCommand } = await import('./commands/wait.js');
    await waitCommand(worktreeId, options);
  });

const worktreeCmd = program.command('worktree').description('Manage worktrees');

worktreeCmd
  .command('create')
  .description('Create a standalone worktree without spawning agents')
  .option('-n, --name <name>', 'Name for the worktree')
  .option('-b, --base <branch>', 'Base branch for the worktree')
  .option('--json', 'Output as JSON')
  .action(async (options) => {
    const { worktreeCreateCommand } = await import('./commands/worktree.js');
    await worktreeCreateCommand(options);
  });

program
  .command('ui')
  .alias('dashboard')
  .description('Open the native dashboard')
  .action(async () => {
    const { uiCommand } = await import('./commands/ui.js');
    await uiCommand();
  });

program
  .command('install-dashboard')
  .description('Download and install the macOS dashboard app')
  .option('--dir <path>', 'Install directory', '/Applications')
  .option('--json', 'JSON output')
  .action(async (options) => {
    const { installDashboardCommand } = await import('./commands/install-dashboard.js');
    await installDashboardCommand(options);
  });

const cronCmd = program.command('cron').description('Manage scheduled runs');

cronCmd
  .command('start')
  .description('Start the cron scheduler daemon in a tmux window')
  .option('--json', 'Output as JSON')
  .action(async (options) => {
    const { cronStartCommand } = await import('./commands/cron.js');
    await cronStartCommand(options);
  });

cronCmd
  .command('stop')
  .description('Stop the cron scheduler daemon')
  .option('--json', 'Output as JSON')
  .action(async (options) => {
    const { cronStopCommand } = await import('./commands/cron.js');
    await cronStopCommand(options);
  });

cronCmd
  .command('list')
  .description('List configured schedules and next run times')
  .option('--json', 'Output as JSON')
  .action(async (options) => {
    const { cronListCommand } = await import('./commands/cron.js');
    await cronListCommand(options);
  });

cronCmd
  .command('status')
  .description('Show cron daemon status and recent log')
  .option('-l, --lines <n>', 'Number of recent log lines to show', (v: string) => Number(v), 20)
  .option('--json', 'Output as JSON')
  .action(async (options) => {
    const { cronStatusCommand } = await import('./commands/cron.js');
    await cronStatusCommand(options);
  });

cronCmd
  .command('_daemon', { hidden: true })
  .description('Internal: run the cron daemon (called by ppg cron start)')
  .action(async () => {
    const { cronDaemonCommand } = await import('./commands/cron.js');
    await cronDaemonCommand();
  });

cronCmd
  .command('add')
  .description('Add a new schedule entry')
  .requiredOption('--name <name>', 'Schedule name')
  .requiredOption('--cron <expression>', 'Cron expression')
  .option('--swarm <name>', 'Swarm template name')
  .option('--prompt <name>', 'Prompt template name')
  .option('--var <key=value...>', 'Template variables', collectVars, [])
  .option('--project <path>', 'Project root path')
  .option('--json', 'Output as JSON')
  .action(async (options) => {
    const { cronAddCommand } = await import('./commands/cron.js');
    await cronAddCommand(options);
  });

cronCmd
  .command('remove')
  .description('Remove a schedule entry')
  .requiredOption('--name <name>', 'Schedule name to remove')
  .option('--project <path>', 'Project root path')
  .option('--json', 'Output as JSON')
  .action(async (options) => {
    const { cronRemoveCommand } = await import('./commands/cron.js');
    await cronRemoveCommand(options);
  });

// Error handling
program.exitOverride();

function collectVars(value: string, previous: string[]): string[] {
  return previous.concat([value]);
}

function parsePositiveInt(optionName: string) {
  return (v: string): number => {
    const n = Number(v);
    if (!Number.isInteger(n) || n < 1) {
      throw new Error(`--${optionName} must be a positive integer`);
    }
    return n;
  };
}

async function main() {
  try {
    await program.parseAsync(process.argv);
  } catch (err) {
    if (err instanceof PpgError) {
      outputError(err, program.opts().json ?? false);
      process.exit(err.exitCode);
    }
    if (err instanceof Error && 'code' in err) {
      const code = (err as { code: string }).code;
      if (code === 'commander.helpDisplayed' || code === 'commander.version') {
        process.exit(0);
      }
    }
    outputError(err, program.opts().json ?? false);
    process.exit(1);
  }
}

main();
