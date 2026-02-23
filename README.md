# ppg — Pure Point Guard

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

### `ppg list templates`

List available prompt templates.

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

## Agent Status Lifecycle

```
spawning → running → completed
                   → failed
                   → killed (via ppg kill)
                   → lost (tmux pane died unexpectedly)
```

Status is determined by checking (in order):
1. Result file exists → `completed`
2. Tmux pane gone → `lost`
3. Pane dead with exit 0 → `completed`
4. Pane dead with non-zero exit → `failed`
5. Pane alive, shell prompt visible → `failed` (agent exited without writing results)
6. Otherwise → `running`

## Conductor Mode

ppg is designed to be driven by a meta-agent (a "conductor"). See `CONDUCTOR.md` for instructions you can give to a Claude Code session to orchestrate parallel work using ppg. The conductor plans tasks, spawns agents, polls status, collects results, and merges branches — all programmatically via `--json` output.

## License

MIT
