# ppg CLI Command Reference

Quick reference for all ppg commands relevant to conductor workflows. Always use `--json` for machine-readable output.

## ppg init

Initialize ppg in the current git repository. Creates `.pg/` directory structure, default config, empty manifest, and sample template.

```bash
ppg init --json
```

**JSON output:**
```json
{ "success": true, "projectRoot": "/path/to/repo", "sessionName": "ppg-repo", "pgDir": "/path/to/repo/.pg" }
```

**Errors:** `NOT_GIT_REPO`, `TMUX_NOT_FOUND`

## ppg spawn

Spawn a new worktree with agent(s), or add agents to an existing worktree.

```bash
# New worktree + agent
ppg spawn --name <name> --prompt <text> --json --no-open

# Multiple agents in new worktree (same prompt)
ppg spawn --name <name> --prompt <text> --count <n> --json --no-open

# Add agent to existing worktree (different prompt)
ppg spawn --worktree <wt-id> --prompt <text> --json --no-open

# Specify base branch
ppg spawn --name <name> --prompt <text> --base <branch> --json --no-open

# Use a template
ppg spawn --name <name> --template <template-name> --var KEY=value --json --no-open

# Use a prompt file
ppg spawn --name <name> --prompt-file /path/to/prompt.md --json --no-open
```

**Options:**

| Flag | Description |
|------|-------------|
| `-n, --name <name>` | Worktree/task name (default: auto-generated ID) |
| `-a, --agent <type>` | Agent type from config (default: `claude`) |
| `-p, --prompt <text>` | Inline prompt text |
| `-f, --prompt-file <path>` | Path to file containing prompt |
| `-t, --template <name>` | Template name from `.pg/templates/` |
| `--var <KEY=value>` | Template variable (repeatable) |
| `-b, --base <branch>` | Base branch (default: current branch) |
| `-w, --worktree <id>` | Add agent to existing worktree instead of creating new one |
| `-c, --count <n>` | Number of agents to spawn (default: 1) |
| `--split` | Put all agents in one window as split panes |
| `--no-open` | Suppress Terminal.app window |
| `--json` | JSON output |

**JSON output (new worktree):**
```json
{
  "success": true,
  "worktree": { "id": "wt-abc123", "name": "task-name", "branch": "ppg/task-name", "path": "/path/.worktrees/wt-abc123", "tmuxWindow": "ppg-repo:1" },
  "agents": [{ "id": "ag-xyz12345", "tmuxTarget": "ppg-repo:1" }]
}
```

**JSON output (existing worktree):**
```json
{
  "success": true,
  "worktree": { "id": "wt-abc123", "name": "task-name" },
  "agents": [{ "id": "ag-new12345", "tmuxTarget": "%16" }]
}
```

**Errors:** `NOT_INITIALIZED`, `WORKTREE_NOT_FOUND` (when using `--worktree`)

## ppg status

Show status of all worktrees and agents. Refreshes agent statuses from tmux before returning.

```bash
ppg status --json                    # All worktrees
ppg status <worktree-id> --json      # Specific worktree
ppg status --watch                   # Live-refresh in terminal
```

**JSON output:**
```json
{
  "session": "ppg-repo",
  "worktrees": {
    "wt-abc123": {
      "id": "wt-abc123",
      "name": "task-name",
      "path": "/path/.worktrees/wt-abc123",
      "branch": "ppg/task-name",
      "baseBranch": "main",
      "status": "active",
      "tmuxWindow": "ppg-repo:1",
      "agents": {
        "ag-xyz12345": {
          "id": "ag-xyz12345",
          "name": "claude",
          "agentType": "claude",
          "status": "running",
          "tmuxTarget": "ppg-repo:1",
          "prompt": "...",
          "resultFile": "/path/.pg/results/ag-xyz12345.md",
          "startedAt": "2025-01-01T00:00:00.000Z"
        }
      },
      "createdAt": "2025-01-01T00:00:00.000Z"
    }
  }
}
```

**Agent statuses:** `spawning` | `running` | `waiting` | `completed` | `failed` | `killed` | `lost`
**Worktree statuses:** `active` | `merging` | `merged` | `failed` | `cleaned`

## ppg kill

Kill running agents. Can target a single agent, all agents in a worktree, or everything.

```bash
ppg kill --agent <agent-id> --json               # Kill one agent
ppg kill --worktree <wt-id> --json               # Kill all agents in worktree
ppg kill --worktree <wt-id> --remove --json      # Kill + remove worktree
ppg kill --all --json                            # Kill everything
ppg kill --all --remove --json                   # Kill everything + cleanup
ppg kill --agent <agent-id> --delete --json      # Kill + delete entry from manifest
ppg kill --worktree <wt-id> --delete --json      # Kill all + delete worktree entry
```

**JSON output:**
```json
{ "success": true, "killed": ["ag-xyz12345"], "removed": false }
```

## ppg aggregate

Collect result files from completed agents.

```bash
ppg aggregate --all --json              # All worktrees
ppg aggregate <worktree-id> --json      # Specific worktree
```

**JSON output:**
```json
{
  "results": [
    {
      "agentId": "ag-xyz12345",
      "worktreeId": "wt-abc123",
      "worktreeName": "task-name",
      "branch": "ppg/task-name",
      "status": "completed",
      "content": "Full text content of the agent's result file..."
    }
  ]
}
```

Results come from `.pg/results/<agentId>.md`. If no result file exists, falls back to tmux pane capture.

## ppg merge

Merge a worktree's branch back into its base branch. Default strategy is squash.

```bash
ppg merge <wt-id> --json                          # Squash merge + cleanup
ppg merge <wt-id> --strategy no-ff --json          # Merge commit (preserves history)
ppg merge <wt-id> --no-cleanup --json              # Merge but keep worktree alive
ppg merge <wt-id> --dry-run                        # Preview without doing anything
ppg merge <wt-id> --force --json                   # Merge even if agents aren't done
```

**JSON output:**
```json
{
  "success": true,
  "worktreeId": "wt-abc123",
  "branch": "ppg/task-name",
  "baseBranch": "main",
  "strategy": "squash",
  "cleaned": true
}
```

**Errors:** `WORKTREE_NOT_FOUND`, merge conflict (git error), agents still running (without `--force`)

Cleanup sequence: kill tmux window, teardown env, `git worktree remove --force`, `git branch -D ppg/<name>`, set manifest status `cleaned`.

## ppg swarm

Run a predefined swarm template — spawns multiple agents from `.pg/swarms/` with prompts from `.pg/prompts/`.

```bash
# Run a swarm template (creates new worktree, spawns all agents)
ppg swarm code-review --var CONTEXT="Review the auth module" --json --no-open

# Run a swarm against an existing worktree (e.g., review a PR's worktree)
ppg swarm code-review --worktree wt-abc123 --var CONTEXT="Review PR #42" --json --no-open

# Override worktree name
ppg swarm code-review --name "auth-review" --var CONTEXT="Review auth changes" --json --no-open

# Target by worktree name
ppg swarm code-review --worktree feature-auth --var CONTEXT="Review auth feature" --json --no-open
```

**Options:**

| Flag | Description |
|------|-------------|
| `-w, --worktree <ref>` | Target existing worktree by ID, name, or branch |
| `--var <KEY=value>` | Template variable (repeatable) |
| `-n, --name <name>` | Override worktree name (default: swarm name) |
| `-b, --base <branch>` | Base branch for new worktree(s) |
| `--no-open` | Suppress Terminal.app windows |
| `--json` | JSON output |

**JSON output (shared strategy):**
```json
{
  "success": true,
  "swarm": "code-review",
  "strategy": "shared",
  "worktree": { "id": "wt-abc123", "name": "code-review", "branch": "ppg/code-review", "path": "/path/.worktrees/wt-abc123", "tmuxWindow": "ppg-repo:1" },
  "agents": [
    { "id": "ag-xyz12345", "tmuxTarget": "ppg-repo:1" },
    { "id": "ag-abc67890", "tmuxTarget": "ppg-repo:2" }
  ]
}
```

**Errors:** `NOT_INITIALIZED`, `INVALID_ARGS` (missing template or prompt file), `WORKTREE_NOT_FOUND`

## ppg list swarms

List available swarm templates.

```bash
ppg list swarms --json
```

**JSON output:**
```json
{ "swarms": [{ "name": "code-review", "description": "Multi-perspective code review", "strategy": "shared", "agents": 3 }] }
```

## ppg logs

View an agent's tmux pane output.

```bash
ppg logs <agent-id> --json                 # Last 100 lines
ppg logs <agent-id> --lines 500 --json     # Last 500 lines
ppg logs <agent-id> --full --json          # Full history
ppg logs <agent-id> --follow --json        # Follow output (poll every 1s)
```

**JSON output:**
```json
{ "agentId": "ag-xyz12345", "status": "running", "tmuxTarget": "ppg-repo:1", "output": "pane content..." }
```

## ppg worktree create

Create a standalone worktree without spawning any agents. Useful when you want to set up the worktree first, then add agents later.

```bash
ppg worktree create --name <name> --json
ppg worktree create --name <name> --base <branch> --json
```

**JSON output:**
```json
{
  "success": true,
  "worktree": { "id": "wt-abc123", "name": "task-name", "branch": "ppg/task-name", "baseBranch": "main", "path": "/path/.worktrees/wt-abc123" }
}
```

## ppg list templates

List available prompt templates.

```bash
ppg list templates --json
```

**JSON output:**
```json
{ "templates": [{ "name": "default", "description": "Task template", "variables": ["TASK_NAME", "PROMPT", "WORKTREE_PATH"] }] }
```

## ppg wait

Block until agents reach a terminal state. Useful as an alternative to manual polling.

```bash
ppg wait --all --json                    # Wait for all agents
ppg wait <wt-id> --json                  # Wait for agents in one worktree
ppg wait --all --timeout 300 --json      # 5-minute timeout
ppg wait --all --interval 10 --json      # Poll every 10s (default: 5s)
```

**Options:**

| Flag | Description |
|------|-------------|
| `--all` | Wait for all agents across all worktrees |
| `--timeout <seconds>` | Timeout in seconds (default: no limit) |
| `--interval <seconds>` | Poll interval in seconds (default: 5) |
| `--json` | JSON output |

**Errors:** `WAIT_TIMEOUT` (timeout elapsed), `AGENTS_FAILED` (agents ended in failed/lost state)

## ppg send

Send text or raw key sequences to an agent's tmux pane.

```bash
ppg send <agent-id> "yes" --json         # Send text + Enter
ppg send <agent-id> "y" --no-enter       # Text without Enter
ppg send <agent-id> "C-c" --keys         # Send raw tmux keys (e.g., Ctrl-C)
```

**Options:**

| Flag | Description |
|------|-------------|
| `--keys` | Send raw tmux key names instead of literal text |
| `--no-enter` | Do not append Enter after the text |
| `--json` | JSON output |

## ppg restart

Restart a failed or killed agent in its existing worktree.

```bash
ppg restart <agent-id> --json                        # Restart with original prompt
ppg restart <agent-id> --prompt "Try again" --json   # Override prompt
ppg restart <agent-id> --agent codex --json           # Override agent type
```

**Options:**

| Flag | Description |
|------|-------------|
| `-p, --prompt <text>` | Override the original prompt |
| `-a, --agent <type>` | Override the agent type |
| `--no-open` | Do not open a Terminal window |
| `--json` | JSON output |

**Errors:** `AGENT_NOT_FOUND`

## ppg diff

Show changes made in a worktree branch compared to its base.

```bash
ppg diff <wt-id> --json                  # Full diff
ppg diff <wt-id> --stat --json           # Diffstat summary
ppg diff <wt-id> --name-only             # Changed file names only
```

**Options:**

| Flag | Description |
|------|-------------|
| `--stat` | Show diffstat summary |
| `--name-only` | Show only changed file names |
| `--json` | JSON output |

**Errors:** `WORKTREE_NOT_FOUND`

## ppg clean

Remove worktrees in terminal states (merged/cleaned, optionally failed).

```bash
ppg clean --json                         # Clean merged/cleaned worktrees
ppg clean --all --json                   # Also clean failed worktrees
ppg clean --dry-run                      # Preview what would be removed
ppg clean --prune                        # Also run git worktree prune
```

**Options:**

| Flag | Description |
|------|-------------|
| `--all` | Also clean failed worktrees |
| `--dry-run` | Show what would be done without doing it |
| `--prune` | Also run `git worktree prune` |
| `--json` | JSON output |

## ppg attach

Open a terminal attached to a worktree or agent tmux pane.

```bash
ppg attach <wt-id-or-name>              # Attach to worktree's tmux window
ppg attach <agent-id>                   # Attach to agent's tmux pane
```

## Error Codes

| Code | Meaning | Recovery |
|------|---------|----------|
| `TMUX_NOT_FOUND` | tmux not installed | Fatal — user must install tmux |
| `NOT_GIT_REPO` | Not inside a git repository | Fatal — user must cd to a repo |
| `NOT_INITIALIZED` | `.pg/` directory missing | Auto-fix: run `ppg init --json` |
| `MANIFEST_LOCK` | Could not acquire manifest lock | Retry after brief delay (rare) |
| `WORKTREE_NOT_FOUND` | Worktree ID/name not in manifest | Check `ppg status --json` for valid IDs |
| `AGENT_NOT_FOUND` | Agent ID not in manifest | Check `ppg status --json` for valid IDs |
| `AGENTS_RUNNING` | Agents still running (e.g., merge without `--force`) | Wait for agents or use `--force` |
| `WAIT_TIMEOUT` | `ppg wait` timed out before agents finished | Increase `--timeout` or kill stuck agents |
| `AGENTS_FAILED` | One or more agents ended in failed/lost state | Check logs, restart, or skip |
| `MERGE_FAILED` | Git merge conflict or other merge error | Resolve conflict manually or skip |
| `INVALID_ARGS` | Invalid command arguments | Check command usage |
