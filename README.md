# ppg — Pure Point Guard

[![CI](https://github.com/2witstudios/ppg-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/2witstudios/ppg-cli/actions/workflows/ci.yml)
[![npm version](https://img.shields.io/npm/v/ppg-cli.svg)](https://www.npmjs.com/package/ppg-cli)
[![license](https://img.shields.io/npm/l/ppg-cli.svg)](https://github.com/2witstudios/ppg-cli/blob/main/LICENSE)

Local orchestration runtime for parallel CLI coding agents.

ppg spawns multiple AI coding agents in isolated git worktrees, each in its own tmux pane, and gives you a single control plane to monitor, aggregate, and merge their work.

## Why

When you have a large task — adding tests across a codebase, refactoring multiple modules, fixing a batch of issues — you can break it into independent units and run them in parallel. ppg handles the plumbing: worktree creation, agent spawning, tmux session management, status tracking, result collection, and branch merging.

It works with any CLI agent (Claude Code, Codex, custom scripts) and is designed to be driven by a human or by a "conductor" meta-agent.

## Requirements

- **Node.js** >= 20
- **git** (with worktree support)
- **tmux**
- **macOS** (Terminal.app auto-open uses AppleScript; tmux features work anywhere)

## Install

```bash
npm install -g ppg-cli
```

## Quick Start

```bash
# Initialize in your project
cd your-project
ppg init

# Spawn an agent
ppg spawn --name fix-auth --prompt "Fix the authentication bug in src/auth.ts"

# Spawn multiple agents in parallel
ppg spawn --name add-tests --prompt "Add unit tests for src/utils/"
ppg spawn --name update-docs --prompt "Update the API documentation"

# Check status
ppg status

# Watch status live
ppg status --watch

# View agent output
ppg logs ag-xxxxxxxx

# Collect results
ppg aggregate --all

# Merge a completed worktree back
ppg merge wt-xxxxxx
```

Each `ppg spawn` creates a git worktree, opens a tmux pane, launches the agent, and pops open a Terminal.app window so you can watch it work.

## How It Works

```
your-project/
├── .pg/
│   ├── config.yaml      # Agent and project config
│   ├── manifest.json     # Runtime state (worktrees, agents, status)
│   ├── templates/        # Reusable prompt templates
│   ├── prompts/          # Generated per-agent prompt files
│   └── results/          # Agent result files
├── .worktrees/
│   ├── wt-abc123/        # Isolated git worktree
│   └── wt-def456/        # Another worktree
└── ...
```

**Worktrees** are isolated git checkouts on their own branches (`ppg/<name>`). Each agent works in its own worktree so there are no file conflicts between parallel agents.

**tmux** provides the process management layer. One session per project, one window per worktree, one pane per agent. This gives you `ppg logs`, `ppg status`, `ppg attach`, and `ppg kill` for free.

**Terminal.app windows** open automatically when agents spawn (macOS), so you can see what every agent is doing without manually attaching. Use `--no-open` to suppress this.

## Commands

### `ppg init`

Initialize ppg in the current git repository. Creates `.pg/` directory with default config and a sample template.

```bash
ppg init
ppg init --json
```

### `ppg spawn`

Spawn a new worktree with agent(s), or add agents to an existing worktree.

```bash
# Inline prompt
ppg spawn --name fix-bug --prompt "Fix the null check in parser.ts"

# From a file
ppg spawn --name refactor --prompt-file tasks/refactor-auth.md

# Using a template with variables
ppg spawn --name add-tests --template test-writer --var SCOPE=auth --var STYLE=unit

# Multiple agents in one worktree
ppg spawn --name big-task --prompt "Implement feature X" --count 2

# Split panes in one window
ppg spawn --name big-task --prompt "Implement feature X" --count 2 --split

# Add agent to existing worktree
ppg spawn --worktree wt-abc123 --prompt "Review the changes"

# Silent mode (no Terminal window)
ppg spawn --name ci-task --prompt "Run linting" --no-open

# Specify base branch
ppg spawn --name hotfix --prompt "Fix critical bug" --base release/v2
```

| Option | Description |
|---|---|
| `-n, --name <name>` | Name for the worktree (becomes branch `ppg/<name>`) |
| `-a, --agent <type>` | Agent type from config (default: `claude`) |
| `-p, --prompt <text>` | Inline prompt text |
| `-f, --prompt-file <path>` | Read prompt from file |
| `-t, --template <name>` | Use a template from `.pg/templates/` |
| `--var <key=value>` | Template variable (repeatable) |
| `-b, --base <branch>` | Base branch for the worktree |
| `-w, --worktree <id>` | Add agent to existing worktree instead of creating new |
| `-c, --count <n>` | Number of agents to spawn (default: 1) |
| `--split` | Put all agents in one window as split panes |
| `--no-open` | Don't open a Terminal window |
| `--json` | JSON output |

### `ppg status`

Show status of all worktrees and agents.

```bash
ppg status              # Pretty table
ppg status --json       # Machine-readable
ppg status --watch      # Live updates
ppg status my-task      # Filter by worktree name
```

### `ppg attach`

Open a terminal attached to a worktree or agent pane. If you're already in tmux, it switches to the target pane. Otherwise it opens a new Terminal.app window.

```bash
ppg attach wt-abc123    # By worktree ID
ppg attach my-task      # By worktree name
ppg attach ag-xxxxxxxx  # By agent ID
```

### `ppg logs`

View captured output from an agent's tmux pane.

```bash
ppg logs ag-xxxxxxxx              # Last 100 lines
ppg logs ag-xxxxxxxx --lines 500  # Last 500 lines
ppg logs ag-xxxxxxxx --follow     # Tail (polls every 1s)
ppg logs ag-xxxxxxxx --full       # Full pane history
```

### `ppg kill`

Kill agents and optionally remove worktrees.

```bash
ppg kill --agent ag-xxxxxxxx       # Kill one agent
ppg kill --worktree wt-abc123      # Kill all agents in worktree
ppg kill --all                     # Kill everything
ppg kill --all --remove            # Kill everything and remove worktrees
```

### `ppg aggregate`

Collect result files from completed agents.

```bash
ppg aggregate wt-abc123            # Results from one worktree
ppg aggregate --all                # Results from all worktrees
ppg aggregate --all -o results.md  # Write to file
```

### `ppg merge`

Merge a worktree branch back into its base branch.

```bash
ppg merge wt-abc123                # Squash merge (default)
ppg merge wt-abc123 -s no-ff      # No-ff merge
ppg merge wt-abc123 --dry-run     # Preview
ppg merge wt-abc123 --no-cleanup  # Keep worktree after merge
ppg merge wt-abc123 --force       # Merge even if agents aren't done
```

### `ppg diff`

Show changes made in a worktree branch relative to its base.

```bash
ppg diff wt-abc123                 # Full diff
ppg diff wt-abc123 --stat          # Diffstat summary
ppg diff wt-abc123 --name-only     # Changed file names only
```

### `ppg restart`

Restart a failed or killed agent in the same worktree.

```bash
ppg restart ag-xxxxxxxx                        # Restart with original prompt
ppg restart ag-xxxxxxxx --prompt "Try again"   # Override the prompt
ppg restart ag-xxxxxxxx --agent codex          # Override the agent type
```

### `ppg send`

Send text or keystrokes to an agent's tmux pane.

```bash
ppg send ag-xxxxxxxx "yes"          # Send text + Enter
ppg send ag-xxxxxxxx "y" --no-enter # Send text without Enter
ppg send ag-xxxxxxxx "C-c" --keys   # Send raw tmux key names
```

### `ppg wait`

Wait for agents to reach a terminal state (completed, failed, killed, lost).

```bash
ppg wait wt-abc123                    # Wait for all agents in worktree
ppg wait --all                        # Wait for all agents everywhere
ppg wait --all --timeout 300          # Timeout after 5 minutes
ppg wait --all --interval 10          # Poll every 10 seconds
```

### `ppg clean`

Remove worktrees in terminal states (merged, cleaned, failed).

```bash
ppg clean                    # Clean merged/cleaned worktrees
ppg clean --all              # Also clean failed worktrees
ppg clean --dry-run          # Preview what would be cleaned
ppg clean --prune            # Also run git worktree prune
```

### `ppg worktree create`

Create a standalone worktree without spawning any agents.

```bash
ppg worktree create --name my-branch
ppg worktree create --name my-branch --base develop
```

### `ppg list templates`

List available prompt templates from `.pg/templates/`.

### `ppg ui`

Open the native macOS dashboard app (alias: `ppg dashboard`).

## Configuration

`.pg/config.yaml`:

```yaml
sessionName: ppg
defaultAgent: claude

agents:
  claude:
    name: claude
    command: claude --dangerously-skip-permissions
    interactive: true
    resultInstructions: >-
      When you have completed the task, write a summary of what you did
      and any important notes to the file at: {{RESULT_FILE}}

worktreeBase: .worktrees
templateDir: .pg/templates
resultDir: .pg/results
logDir: .pg/logs
envFiles:
  - .env
  - .env.local
symlinkNodeModules: true
```

### Custom Agents

Add any CLI agent by defining it in the agents map:

```yaml
agents:
  claude:
    name: claude
    command: claude --dangerously-skip-permissions
    interactive: true

  codex:
    name: codex
    command: codex
    promptFlag: --prompt
    interactive: true

  custom-script:
    name: custom
    command: ./scripts/my-agent.sh
    promptFlag: --task
    interactive: false
```

Then spawn with `ppg spawn --agent codex --prompt "..."`.

## Templates

Templates live in `.pg/templates/` as Markdown files with `{{VAR}}` placeholders.

**Built-in variables:**

| Variable | Value |
|---|---|
| `{{WORKTREE_PATH}}` | Path to the agent's worktree |
| `{{BRANCH}}` | Git branch name |
| `{{AGENT_ID}}` | Agent identifier |
| `{{RESULT_FILE}}` | Where the agent should write results |
| `{{PROJECT_ROOT}}` | Repository root path |
| `{{TASK_NAME}}` | Worktree name |
| `{{PROMPT}}` | The prompt text |

Custom variables are passed with `--var KEY=VALUE`.

**Example template** (`.pg/templates/test-writer.md`):

```markdown
# Task: {{TASK_NAME}}

Write comprehensive tests for the {{SCOPE}} module.

## Working Directory
{{WORKTREE_PATH}}

## Guidelines
- Use {{FRAMEWORK}} for test framework
- Aim for >90% coverage
- Write your summary to {{RESULT_FILE}} when done
```

```bash
ppg spawn --name auth-tests --template test-writer --var SCOPE=auth --var FRAMEWORK=vitest
```

## Agent Lifecycle

```
spawning → running → completed   (result file written)
                   → failed      (non-zero exit or shell prompt visible)
                   → killed      (via ppg kill)
                   → lost        (tmux pane died unexpectedly)
```

Status is determined by checking (in order):
1. Result file exists → `completed`
2. Tmux pane gone → `lost`
3. Pane dead with exit 0 → `completed`
4. Pane dead with non-zero exit → `failed`
5. Pane alive, shell prompt visible → `failed` (agent exited without writing results)
6. Otherwise → `running`

## Conductor Mode

ppg is designed to be driven programmatically by a meta-agent (a "conductor"). Every command supports `--json` for machine-readable output.

**Conductor workflow:**

```bash
# 1. Plan — break the task into independent units
# 2. Spawn agents
ppg spawn --name task-1 --prompt "Do X" --json
ppg spawn --name task-2 --prompt "Do Y" --json

# 3. Poll for completion
ppg status --json   # check for status: "completed" or "failed"

# 4. Wait for all agents
ppg wait --all --json

# 5. Aggregate results
ppg aggregate --all --json

# 6. Merge completed work
ppg merge wt-xxxxxx --json
```

Key principles:
- Always use `--json` for machine-readable output
- Poll status every 5 seconds or use `ppg wait`
- One concern per worktree for clean merges
- Use `ppg aggregate` to collect and review results before merging

## Architecture

```
src/
├── cli.ts              # Entry point — registers commands with Commander.js
├── commands/           # Command implementations
├── core/               # Domain logic (manifest, agent, worktree, tmux, terminal, config)
├── lib/                # Utilities (paths, errors, id, output, shell)
└── types/              # Type definitions
```

Built with TypeScript (strict, ES2022, ESM-only), Commander.js for CLI framework, and tmux + git worktrees as foundational abstractions. See [CONTRIBUTING.md](CONTRIBUTING.md) for development details.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, testing, and code conventions.

## License

[MIT](LICENSE)
