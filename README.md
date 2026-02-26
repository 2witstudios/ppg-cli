# ppg — Pure Point Guard

[![CI](https://github.com/2witstudios/ppg-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/2witstudios/ppg-cli/actions/workflows/ci.yml)
[![npm version](https://img.shields.io/npm/v/pure-point-guard.svg)](https://www.npmjs.com/package/pure-point-guard)
[![license](https://img.shields.io/npm/l/pure-point-guard.svg)](https://github.com/2witstudios/ppg-cli/blob/main/LICENSE)

A native macOS dashboard for orchestrating parallel AI coding agents.

Spawn, monitor, and merge multiple AI agents working in parallel — each isolated in its own git worktree. Watch them all from a single window.

![ppg dashboard](screenshot.png)

## Features

**Multi-agent dashboard** — See all your projects, worktrees, and agents in one place. Each agent gets a live terminal pane so you can watch it work in real time.

**Command palette** — Hit a key to spawn a new agent (Claude, Codex, OpenCode), open a terminal, or create a worktree. Type a prompt and it's running in seconds.

**Agent-agnostic** — Works with Claude Code, Codex, OpenCode, or any CLI agent. Define custom agents in config.

**Git worktree isolation** — Every agent works in its own worktree on its own branch. No file conflicts, clean merges.

**Prompts editor** — Write and manage reusable prompt templates with `{{VAR}}` substitution, right inside the app.

**Swarms** — Define multi-agent orchestrations in YAML. Choose shared or isolated strategies. Launch coordinated agent groups.

**Project overview** — Home dashboard shows all your projects with commit heatmaps, recent commits, agent status, and worktree counts at a glance.

**Inline rename** — Click any agent, terminal, or worktree name in the sidebar to rename it.

**Split panes** — Run multiple agents in the same worktree with split terminal views.

**Cron scheduling** — Define recurring agent tasks in `.ppg/schedules.yaml`. The daemon triggers swarms or prompts on cron expressions. Manage from the Schedules dashboard tab or `ppg cron` CLI.

**Global prompts & templates** — Put prompts, templates, and swarms in `~/.ppg/` to share them across all projects. Project-local always takes precedence.

**Customizable** — Appearance modes (light/dark/system), terminal font and size, keybinding customization, configurable shell.

## Install

### Dashboard (macOS app)

The dashboard is the primary interface. Download from [GitHub Releases](https://github.com/2witstudios/ppg-cli/releases/latest) — grab the `.dmg` file.

Or install via CLI:

```bash
ppg install-dashboard
```

### CLI (runtime engine)

The CLI is the engine that powers the dashboard. Install it globally:

```bash
npm install -g pure-point-guard
```

**Requirements:** Node.js >= 20, git, tmux (`brew install tmux`), macOS

### Claude Code integration

Running `ppg init` in any project automatically installs the `/ppg` skill for Claude Code. This gives Claude the ability to orchestrate parallel agents — just type `/ppg` in any Claude Code session.

## Quick Start

```bash
# 1. Initialize ppg in your project
cd your-project
ppg init

# 2. Open the dashboard
ppg ui
```

From the dashboard, use the command palette to spawn agents, watch their progress in real time, and merge completed work.

### Or use the CLI directly

```bash
# Spawn agents
ppg spawn --name fix-auth --prompt "Fix the authentication bug in src/auth.ts"
ppg spawn --name add-tests --prompt "Add unit tests for src/utils/"
ppg spawn --name update-docs --prompt "Update the API documentation"

# Check status
ppg status

# Collect results
ppg aggregate --all

# Merge completed work
ppg merge wt-xxxxxx
```

## How It Works

Each `ppg spawn` creates a git worktree on a `ppg/<name>` branch, opens a tmux pane, and launches the agent. The dashboard watches the manifest file in real time — no IPC, no server.

```
your-project/
├── .ppg/
│   ├── config.yaml      # Agent and project config
│   ├── manifest.json     # Runtime state (worktrees, agents, status)
│   ├── templates/        # Reusable prompt templates
│   ├── prompts/          # Prompt files for swarms
│   └── results/          # Agent result files
├── .worktrees/
│   ├── wt-abc123/        # Isolated git worktree
│   └── wt-def456/        # Another worktree
└── ...
```

**Agent lifecycle:**

```
spawning → running → completed   (result file written)
                   → failed      (non-zero exit or shell prompt visible)
                   → killed      (via ppg kill)
                   → lost        (tmux pane died unexpectedly)
```

## Configuration

`.ppg/config.yaml`:

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

worktreeBase: .worktrees
templateDir: .ppg/templates
resultDir: .ppg/results
logDir: .ppg/logs
envFiles:
  - .env
  - .env.local
symlinkNodeModules: true
```

## Templates

Templates live in `.ppg/templates/` as Markdown files with `{{VAR}}` placeholders. The prompts editor in the dashboard lets you create and edit these visually.

**Built-in variables:** `{{WORKTREE_PATH}}`, `{{BRANCH}}`, `{{AGENT_ID}}`, `{{RESULT_FILE}}`, `{{PROJECT_ROOT}}`, `{{TASK_NAME}}`, `{{PROMPT}}`

Custom variables are passed with `--var KEY=VALUE` or defined in swarm YAML.

## Global Prompts & Templates

Put prompts, templates, and swarms in `~/.ppg/` to make them available across all projects:

```
~/.ppg/
├── prompts/       # Global prompt files
├── templates/     # Global templates
└── swarms/        # Global swarm definitions
```

Project-local files always take precedence when names conflict. Use `ppg list prompts` or `ppg list templates` to see both local and global entries.

## Cron Scheduling

Define recurring agent tasks in `.ppg/schedules.yaml`:

```yaml
schedules:
  - name: nightly-review
    swarm: code-review
    cron: '0 2 * * *'
    vars:
      CONTEXT: 'Review all changes from the last 24 hours'
  - name: hourly-lint
    prompt: lint-check
    cron: '0 * * * *'
```

```bash
ppg cron start    # Start the scheduler daemon
ppg cron list     # Show schedules with next run times
ppg cron status   # Check daemon status
ppg cron stop     # Stop the daemon
```

Manage schedules visually from the Schedules tab in the dashboard.

## CLI Reference

All commands support `--json` for machine-readable output.

| Command | Description |
|---|---|
| `ppg init` | Initialize ppg in the current git repo |
| `ppg spawn` | Spawn a worktree with agent(s) |
| `ppg status` | Show status of all worktrees and agents |
| `ppg attach` | Open a terminal attached to a worktree or agent |
| `ppg logs` | View agent output from tmux pane |
| `ppg kill` | Kill agents and optionally remove worktrees |
| `ppg aggregate` | Collect result files from completed agents |
| `ppg merge` | Merge a worktree branch back into base |
| `ppg diff` | Show changes in a worktree branch |
| `ppg restart` | Restart a failed or killed agent |
| `ppg send` | Send text or keystrokes to an agent pane |
| `ppg wait` | Wait for agents to complete |
| `ppg clean` | Remove worktrees in terminal states |
| `ppg worktree create` | Create a standalone worktree |
| `ppg list templates` | List available prompt templates |
| `ppg list prompts` | List available prompt files |
| `ppg prompt` | Spawn an agent from a prompt file |
| `ppg cron start` | Start the cron scheduler daemon |
| `ppg cron stop` | Stop the cron scheduler daemon |
| `ppg cron list` | Show configured schedules with next run times |
| `ppg cron status` | Show daemon status and recent log entries |
| `ppg install-dashboard` | Download and install the macOS dashboard |
| `ppg ui` | Open the dashboard |

Run `ppg <command> --help` for detailed options.

## Conductor Mode

ppg is designed to be driven programmatically by a meta-agent (a "conductor"). All commands support `--json` for machine consumption.

```bash
# 1. Spawn agents
ppg spawn --name task-1 --prompt "Do X" --json
ppg spawn --name task-2 --prompt "Do Y" --json

# 2. Wait for completion
ppg wait --all --json

# 3. Aggregate results
ppg aggregate --all --json

# 4. Merge completed work
ppg merge wt-xxxxxx --json
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, testing, and code conventions.

## License

[MIT](LICENSE)
