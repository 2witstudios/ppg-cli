# pogu — pointguard

[![CI](https://github.com/2witstudios/pogu-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/2witstudios/pogu-cli/actions/workflows/ci.yml)
[![npm version](https://img.shields.io/npm/v/pointguard.svg)](https://www.npmjs.com/package/pointguard)
[![license](https://img.shields.io/npm/l/pointguard.svg)](https://github.com/2witstudios/pogu-cli/blob/main/LICENSE)

A native macOS dashboard for orchestrating parallel AI coding agents.

Spawn, monitor, and merge multiple AI agents working in parallel — each isolated in its own git worktree. Watch them all from a single window.

![pogu dashboard](screenshot.png)

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

**Customizable** — Appearance modes (light/dark/system), terminal font and size, keybinding customization, configurable shell.

## Install

### Dashboard (macOS app)

The dashboard is the primary interface. Download from [GitHub Releases](https://github.com/2witstudios/pogu-cli/releases/latest) — grab the `.dmg` file.

Or install via CLI:

```bash
pogu install-dashboard
```

### CLI (runtime engine)

The CLI is the engine that powers the dashboard. Install it globally:

```bash
npm install -g pointguard
```

**Requirements:** Node.js >= 20, git, tmux (`brew install tmux`), macOS

### Claude Code integration

Running `pogu init` in any project automatically installs the `/pogu` skill for Claude Code. This gives Claude the ability to orchestrate parallel agents — just type `/pogu` in any Claude Code session.

## Quick Start

```bash
# 1. Initialize pogu in your project
cd your-project
pogu init

# 2. Open the dashboard
pogu ui
```

From the dashboard, use the command palette to spawn agents, watch their progress in real time, and merge completed work.

### Or use the CLI directly

```bash
# Spawn agents
pogu spawn --name fix-auth --prompt "Fix the authentication bug in src/auth.ts"
pogu spawn --name add-tests --prompt "Add unit tests for src/utils/"
pogu spawn --name update-docs --prompt "Update the API documentation"

# Check status
pogu status

# Collect results
pogu aggregate --all

# Merge completed work
pogu merge wt-xxxxxx
```

## How It Works

Each `pogu spawn` creates a git worktree on a `pogu/<name>` branch, opens a tmux pane, and launches the agent. The dashboard watches the manifest file in real time — no IPC, no server.

```
your-project/
├── .pogu/
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
                   → killed      (via pogu kill)
                   → lost        (tmux pane died unexpectedly)
```

## Configuration

`.pogu/config.yaml`:

```yaml
sessionName: pogu
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
templateDir: .pogu/templates
resultDir: .pogu/results
logDir: .pogu/logs
envFiles:
  - .env
  - .env.local
symlinkNodeModules: true
```

## Templates

Templates live in `.pogu/templates/` as Markdown files with `{{VAR}}` placeholders. The prompts editor in the dashboard lets you create and edit these visually.

**Built-in variables:** `{{WORKTREE_PATH}}`, `{{BRANCH}}`, `{{AGENT_ID}}`, `{{RESULT_FILE}}`, `{{PROJECT_ROOT}}`, `{{TASK_NAME}}`, `{{PROMPT}}`

Custom variables are passed with `--var KEY=VALUE` or defined in swarm YAML.

## CLI Reference

All commands support `--json` for machine-readable output.

| Command | Description |
|---|---|
| `pogu init` | Initialize pogu in the current git repo |
| `pogu spawn` | Spawn a worktree with agent(s) |
| `pogu status` | Show status of all worktrees and agents |
| `pogu attach` | Open a terminal attached to a worktree or agent |
| `pogu logs` | View agent output from tmux pane |
| `pogu kill` | Kill agents and optionally remove worktrees |
| `pogu aggregate` | Collect result files from completed agents |
| `pogu merge` | Merge a worktree branch back into base |
| `pogu diff` | Show changes in a worktree branch |
| `pogu restart` | Restart a failed or killed agent |
| `pogu send` | Send text or keystrokes to an agent pane |
| `pogu wait` | Wait for agents to complete |
| `pogu clean` | Remove worktrees in terminal states |
| `pogu worktree create` | Create a standalone worktree |
| `pogu list templates` | List available prompt templates |
| `pogu install-dashboard` | Download and install the macOS dashboard |
| `pogu ui` | Open the dashboard |

Run `pogu <command> --help` for detailed options.

## Conductor Mode

pogu is designed to be driven programmatically by a meta-agent (a "conductor"). All commands support `--json` for machine consumption.

```bash
# 1. Spawn agents
pogu spawn --name task-1 --prompt "Do X" --json
pogu spawn --name task-2 --prompt "Do Y" --json

# 2. Wait for completion
pogu wait --all --json

# 3. Aggregate results
pogu aggregate --all --json

# 4. Merge completed work
pogu merge wt-xxxxxx --json
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, testing, and code conventions.

## License

[MIT](LICENSE)
