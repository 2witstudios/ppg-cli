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

## ppg logs

View an agent's tmux pane output.

```bash
ppg logs <agent-id> --json                 # Last 100 lines
ppg logs <agent-id> --lines 500 --json     # Last 500 lines
ppg logs <agent-id> --full --json          # Full history
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

## Error Codes

| Code | Meaning | Recovery |
|------|---------|----------|
| `TMUX_NOT_FOUND` | tmux not installed | Fatal — user must install tmux |
| `NOT_GIT_REPO` | Not inside a git repository | Fatal — user must cd to a repo |
| `NOT_INITIALIZED` | `.pg/` directory missing | Auto-fix: run `ppg init --json` |
| `MANIFEST_LOCK` | Could not acquire manifest lock | Retry after brief delay (rare) |
| `WORKTREE_NOT_FOUND` | Worktree ID/name not in manifest | Check `ppg status --json` for valid IDs |
| `AGENT_NOT_FOUND` | Agent ID not in manifest | Check `ppg status --json` for valid IDs |
