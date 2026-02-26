# pogu CLI Command Reference

Quick reference for all pogu commands relevant to conductor workflows. Always use `--json` for machine-readable output.

## pogu init

Initialize pogu in the current git repository. Creates `.pogu/` directory structure, default config, empty manifest, and sample template.

```bash
pogu init --json
```

**JSON output:**
```json
{ "success": true, "projectRoot": "/path/to/repo", "sessionName": "pogu-repo", "poguDir": "/path/to/repo/.pogu" }
```

**Errors:** `NOT_GIT_REPO`, `TMUX_NOT_FOUND`

## pogu spawn

Spawn a new worktree with agent(s), or add agents to an existing worktree.

```bash
# New worktree + agent
pogu spawn --name <name> --prompt <text> --json --no-open

# Multiple agents in new worktree (same prompt)
pogu spawn --name <name> --prompt <text> --count <n> --json --no-open

# Add agent to existing worktree (different prompt)
pogu spawn --worktree <wt-id> --prompt <text> --json --no-open

# Specify base branch
pogu spawn --name <name> --prompt <text> --base <branch> --json --no-open

# Use a template
pogu spawn --name <name> --template <template-name> --var KEY=value --json --no-open

# Use a prompt file
pogu spawn --name <name> --prompt-file /path/to/prompt.md --json --no-open
```

**Options:**

| Flag | Description |
|------|-------------|
| `-n, --name <name>` | Worktree/task name (default: auto-generated ID) |
| `-a, --agent <type>` | Agent type from config (default: `claude`) |
| `-p, --prompt <text>` | Inline prompt text |
| `-f, --prompt-file <path>` | Path to file containing prompt |
| `-t, --template <name>` | Template name from `.pogu/templates/` |
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
  "worktree": { "id": "wt-abc123", "name": "task-name", "branch": "pogu/task-name", "path": "/path/.worktrees/wt-abc123", "tmuxWindow": "pogu-repo:1" },
  "agents": [{ "id": "ag-xyz12345", "tmuxTarget": "pogu-repo:1" }]
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

## pogu status

Show status of all worktrees and agents. Refreshes agent statuses from tmux before returning.

```bash
pogu status --json                    # All worktrees
pogu status <worktree-id> --json      # Specific worktree
pogu status --watch                   # Live-refresh in terminal
```

**JSON output:**
```json
{
  "session": "pogu-repo",
  "worktrees": {
    "wt-abc123": {
      "id": "wt-abc123",
      "name": "task-name",
      "path": "/path/.worktrees/wt-abc123",
      "branch": "pogu/task-name",
      "baseBranch": "main",
      "status": "active",
      "tmuxWindow": "pogu-repo:1",
      "agents": {
        "ag-xyz12345": {
          "id": "ag-xyz12345",
          "name": "claude",
          "agentType": "claude",
          "status": "running",
          "tmuxTarget": "pogu-repo:1",
          "prompt": "...",
          "resultFile": "/path/.pogu/results/ag-xyz12345.md",
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

## pogu kill

Kill running agents. Can target a single agent, all agents in a worktree, or everything.

```bash
pogu kill --agent <agent-id> --json               # Kill one agent
pogu kill --worktree <wt-id> --json               # Kill all agents in worktree
pogu kill --worktree <wt-id> --remove --json      # Kill + remove worktree
pogu kill --all --json                            # Kill everything
pogu kill --all --remove --json                   # Kill everything + cleanup
pogu kill --agent <agent-id> --delete --json      # Kill + delete entry from manifest
pogu kill --worktree <wt-id> --delete --json      # Kill all + delete worktree entry
```

**JSON output:**
```json
{ "success": true, "killed": ["ag-xyz12345"], "removed": false }
```

## pogu aggregate

Collect result files from completed agents.

```bash
pogu aggregate --all --json              # All worktrees
pogu aggregate <worktree-id> --json      # Specific worktree
```

**JSON output:**
```json
{
  "results": [
    {
      "agentId": "ag-xyz12345",
      "worktreeId": "wt-abc123",
      "worktreeName": "task-name",
      "branch": "pogu/task-name",
      "status": "completed",
      "content": "Full text content of the agent's result file..."
    }
  ]
}
```

Results come from `.pogu/results/<agentId>.md`. If no result file exists, falls back to tmux pane capture.

## pogu pr

Create a GitHub PR from a worktree's branch. Pushes the branch to origin and runs `gh pr create`.

```bash
pogu pr <wt-id> --json                          # Create PR (title = worktree name, body = agent results)
pogu pr <wt-id> --title "Fix auth bug" --json   # Custom title
pogu pr <wt-id> --body "Description" --json     # Custom body
pogu pr <wt-id> --draft --json                  # Create as draft PR
```

**Options:**

| Flag | Description |
|------|-------------|
| `--title <text>` | PR title (default: worktree name) |
| `--body <text>` | PR body (default: agent result file content) |
| `--draft` | Create as draft PR |
| `--json` | JSON output |

**JSON output:**
```json
{
  "success": true,
  "worktreeId": "wt-abc123",
  "branch": "pogu/fix-auth-bug",
  "baseBranch": "main",
  "prUrl": "https://github.com/user/repo/pull/42"
}
```

**Errors:** `WORKTREE_NOT_FOUND`, `INVALID_ARGS` (gh not installed, push failed, PR creation failed)

**Notes:**
- Requires GitHub CLI (`gh`) to be installed and authenticated
- Stores the PR URL in the manifest (`prUrl` field on the worktree entry)
- Does NOT merge or clean up the worktree — the branch stays alive for the PR lifecycle

## pogu reset

Nuclear cleanup: kill all agents, remove all worktrees, wipe manifest entries. Includes safety checks.

```bash
pogu reset --json                    # Reset (refuses if unmerged/un-PR'd work exists)
pogu reset --force --json            # Force reset even with unmerged work
pogu reset --force --prune --json    # Force reset + git worktree prune
```

**Options:**

| Flag | Description |
|------|-------------|
| `--force` | Reset even if worktrees have completed work that hasn't been merged or PR'd |
| `--prune` | Also run `git worktree prune` |
| `--json` | JSON output |

**JSON output:**
```json
{
  "success": true,
  "killed": ["ag-xyz12345", "ag-abc67890"],
  "removed": ["wt-abc123", "wt-def456"],
  "warned": ["fix-auth-bug"],
  "pruned": false
}
```

**Safety:** Without `--force`, refuses to reset if any worktree has completed agents but no PR URL and isn't merged. This prevents accidental loss of work.

**Errors:** `NOT_INITIALIZED`, `AGENTS_RUNNING` (without `--force`, when unmerged work exists)

## pogu merge

Merge a worktree's branch back into its base branch. Default strategy is squash.

```bash
pogu merge <wt-id> --json                          # Squash merge + cleanup
pogu merge <wt-id> --strategy no-ff --json          # Merge commit (preserves history)
pogu merge <wt-id> --no-cleanup --json              # Merge but keep worktree alive
pogu merge <wt-id> --dry-run                        # Preview without doing anything
pogu merge <wt-id> --force --json                   # Merge even if agents aren't done
```

**JSON output:**
```json
{
  "success": true,
  "worktreeId": "wt-abc123",
  "branch": "pogu/task-name",
  "baseBranch": "main",
  "strategy": "squash",
  "cleaned": true
}
```

**Errors:** `WORKTREE_NOT_FOUND`, merge conflict (git error), agents still running (without `--force`)

Cleanup sequence: kill tmux window, teardown env, `git worktree remove --force`, `git branch -D pogu/<name>`, set manifest status `cleaned`.

## pogu swarm

Run a predefined swarm template — spawns multiple agents from `.pogu/swarms/` with prompts from `.pogu/prompts/`.

```bash
# Run a swarm template (creates new worktree, spawns all agents)
pogu swarm code-review --var CONTEXT="Review the auth module" --json --no-open

# Run a swarm against an existing worktree (e.g., review a PR's worktree)
pogu swarm code-review --worktree wt-abc123 --var CONTEXT="Review PR #42" --json --no-open

# Override worktree name
pogu swarm code-review --name "auth-review" --var CONTEXT="Review auth changes" --json --no-open

# Target by worktree name
pogu swarm code-review --worktree feature-auth --var CONTEXT="Review auth feature" --json --no-open
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
  "worktree": { "id": "wt-abc123", "name": "code-review", "branch": "pogu/code-review", "path": "/path/.worktrees/wt-abc123", "tmuxWindow": "pogu-repo:1" },
  "agents": [
    { "id": "ag-xyz12345", "tmuxTarget": "pogu-repo:1" },
    { "id": "ag-abc67890", "tmuxTarget": "pogu-repo:2" }
  ]
}
```

**Errors:** `NOT_INITIALIZED`, `INVALID_ARGS` (missing template or prompt file), `WORKTREE_NOT_FOUND`

## pogu list swarms

List available swarm templates.

```bash
pogu list swarms --json
```

**JSON output:**
```json
{ "swarms": [{ "name": "code-review", "description": "Multi-perspective code review", "strategy": "shared", "agents": 3 }] }
```

## pogu logs

View an agent's tmux pane output.

```bash
pogu logs <agent-id> --json                 # Last 100 lines
pogu logs <agent-id> --lines 500 --json     # Last 500 lines
pogu logs <agent-id> --full --json          # Full history
pogu logs <agent-id> --follow --json        # Follow output (poll every 1s)
```

**JSON output:**
```json
{ "agentId": "ag-xyz12345", "status": "running", "tmuxTarget": "pogu-repo:1", "output": "pane content..." }
```

## pogu worktree create

Create a standalone worktree without spawning any agents. Useful when you want to set up the worktree first, then add agents later.

```bash
pogu worktree create --name <name> --json
pogu worktree create --name <name> --base <branch> --json
```

**JSON output:**
```json
{
  "success": true,
  "worktree": { "id": "wt-abc123", "name": "task-name", "branch": "pogu/task-name", "baseBranch": "main", "path": "/path/.worktrees/wt-abc123" }
}
```

## pogu list templates

List available prompt templates.

```bash
pogu list templates --json
```

**JSON output:**
```json
{ "templates": [{ "name": "default", "description": "Task template", "variables": ["TASK_NAME", "PROMPT", "WORKTREE_PATH"] }] }
```

## pogu wait

Block until agents reach a terminal state. Useful as an alternative to manual polling.

```bash
pogu wait --all --json                    # Wait for all agents
pogu wait <wt-id> --json                  # Wait for agents in one worktree
pogu wait --all --timeout 300 --json      # 5-minute timeout
pogu wait --all --interval 10 --json      # Poll every 10s (default: 5s)
```

**Options:**

| Flag | Description |
|------|-------------|
| `--all` | Wait for all agents across all worktrees |
| `--timeout <seconds>` | Timeout in seconds (default: no limit) |
| `--interval <seconds>` | Poll interval in seconds (default: 5) |
| `--json` | JSON output |

**Errors:** `WAIT_TIMEOUT` (timeout elapsed), `AGENTS_FAILED` (agents ended in failed/lost state)

## pogu send

Send text or raw key sequences to an agent's tmux pane.

```bash
pogu send <agent-id> "yes" --json         # Send text + Enter
pogu send <agent-id> "y" --no-enter       # Text without Enter
pogu send <agent-id> "C-c" --keys         # Send raw tmux keys (e.g., Ctrl-C)
```

**Options:**

| Flag | Description |
|------|-------------|
| `--keys` | Send raw tmux key names instead of literal text |
| `--no-enter` | Do not append Enter after the text |
| `--json` | JSON output |

## pogu restart

Restart a failed or killed agent in its existing worktree.

```bash
pogu restart <agent-id> --json                        # Restart with original prompt
pogu restart <agent-id> --prompt "Try again" --json   # Override prompt
pogu restart <agent-id> --agent codex --json           # Override agent type
```

**Options:**

| Flag | Description |
|------|-------------|
| `-p, --prompt <text>` | Override the original prompt |
| `-a, --agent <type>` | Override the agent type |
| `--no-open` | Do not open a Terminal window |
| `--json` | JSON output |

**Errors:** `AGENT_NOT_FOUND`

## pogu diff

Show changes made in a worktree branch compared to its base.

```bash
pogu diff <wt-id> --json                  # Full diff
pogu diff <wt-id> --stat --json           # Diffstat summary
pogu diff <wt-id> --name-only             # Changed file names only
```

**Options:**

| Flag | Description |
|------|-------------|
| `--stat` | Show diffstat summary |
| `--name-only` | Show only changed file names |
| `--json` | JSON output |

**Errors:** `WORKTREE_NOT_FOUND`

## pogu clean

Remove worktrees in terminal states (merged/cleaned, optionally failed).

```bash
pogu clean --json                         # Clean merged/cleaned worktrees
pogu clean --all --json                   # Also clean failed worktrees
pogu clean --dry-run                      # Preview what would be removed
pogu clean --prune                        # Also run git worktree prune
```

**Options:**

| Flag | Description |
|------|-------------|
| `--all` | Also clean failed worktrees |
| `--dry-run` | Show what would be done without doing it |
| `--prune` | Also run `git worktree prune` |
| `--json` | JSON output |

## pogu attach

Open a terminal attached to a worktree or agent tmux pane.

```bash
pogu attach <wt-id-or-name>              # Attach to worktree's tmux window
pogu attach <agent-id>                   # Attach to agent's tmux pane
```

## Error Codes

| Code | Meaning | Recovery |
|------|---------|----------|
| `TMUX_NOT_FOUND` | tmux not installed | Fatal — user must install tmux |
| `NOT_GIT_REPO` | Not inside a git repository | Fatal — user must cd to a repo |
| `NOT_INITIALIZED` | `.pogu/` directory missing | Auto-fix: run `pogu init --json` |
| `MANIFEST_LOCK` | Could not acquire manifest lock | Retry after brief delay (rare) |
| `WORKTREE_NOT_FOUND` | Worktree ID/name not in manifest | Check `pogu status --json` for valid IDs |
| `AGENT_NOT_FOUND` | Agent ID not in manifest | Check `pogu status --json` for valid IDs |
| `AGENTS_RUNNING` | Agents still running (e.g., merge without `--force`) | Wait for agents or use `--force` |
| `WAIT_TIMEOUT` | `pogu wait` timed out before agents finished | Increase `--timeout` or kill stuck agents |
| `AGENTS_FAILED` | One or more agents ended in failed/lost state | Check logs, restart, or skip |
| `MERGE_FAILED` | Git merge conflict or other merge error | Resolve conflict manually or skip |
| `INVALID_ARGS` | Invalid command arguments | Check command usage |
