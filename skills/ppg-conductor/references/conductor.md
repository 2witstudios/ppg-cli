# Conductor Loop Protocol

The conductor loop has 5 phases: Spawn, Poll, Aggregate, Present, Summary.

## Phase 1: Spawn

For each task, run `ppg spawn` and capture the JSON output.

```bash
ppg spawn --name "<name>" --prompt "<self-contained prompt>" --json --no-open
```

**Track the output.** Each spawn returns:
```json
{
  "success": true,
  "worktree": { "id": "wt-abc123", "name": "task-name", "branch": "ppg/task-name", "path": "/path/to/.worktrees/wt-abc123", "tmuxWindow": "ppg-project:1" },
  "agents": [{ "id": "ag-xyz12345", "tmuxTarget": "ppg-project:1" }]
}
```

**Store a tracking table** with: worktree ID, agent IDs, name, and branch for each spawned task.

**Swarm templates** — If a matching swarm template exists in `.ppg/swarms/`, prefer `ppg swarm` over manual multi-spawn:
```bash
# Use a predefined swarm template (much simpler than manual spawning)
ppg swarm code-review --var CONTEXT="Review the auth module" --json --no-open

# Run a swarm against an existing worktree (e.g., review a PR's worktree)
ppg swarm code-review --worktree wt-abc123 --var CONTEXT="Review PR #42" --json --no-open
```

Check available swarms: `ppg list swarms --json`

For **custom swarm mode** (when no template matches), spawn the first agent (creates the worktree), then use `--worktree <wt-id>` for subsequent agents:
```bash
# First agent — creates the worktree
ppg spawn --name "review" --prompt "Focus on code quality..." --json --no-open
# Additional agents — join existing worktree
ppg spawn --worktree wt-abc123 --prompt "Focus on security..." --json --no-open
ppg spawn --worktree wt-abc123 --prompt "Focus on performance..." --json --no-open
```

**Error handling during spawn:**
- If spawn fails, report the error and continue with remaining tasks
- Common errors: `NOT_INITIALIZED` (auto-fix with `ppg init`), `TMUX_NOT_FOUND` (fatal — tell user to install tmux)

## Phase 2: Poll

Poll `ppg status --json` every 5 seconds until all agents reach a terminal state.

```bash
ppg status --json
```

Returns:
```json
{
  "session": "ppg-project",
  "worktrees": {
    "wt-abc123": {
      "id": "wt-abc123",
      "name": "task-name",
      "status": "active",
      "branch": "ppg/task-name",
      "agents": {
        "ag-xyz12345": {
          "id": "ag-xyz12345",
          "status": "running",
          "agentType": "claude",
          "startedAt": "2025-01-01T00:00:00.000Z"
        }
      }
    }
  }
}
```

**Terminal states** for agents: `completed`, `failed`, `killed`, `lost`
**Non-terminal states**: `spawning`, `running`, `waiting`

**Polling behavior:**
- Show a brief status update each cycle: `"Polling... 2/5 agents completed, 3 running"`
- After **2 minutes**: mention that agents are still running and show elapsed time
- After **10 minutes**: warn the user and offer to continue waiting or kill remaining agents
- On `failed` or `lost`: immediately report the agent ID and worktree, offer to re-spawn or skip

**Stop polling when:** all tracked agents are in terminal states.

**Alternative — `ppg wait`:**
Instead of manual polling, you can block until all agents finish:
```bash
ppg wait --all --json --timeout 600
```
This blocks until all agents reach a terminal state or the timeout is hit. Use manual polling (above) when you need progress updates; use `ppg wait` when you just need to block.

## Phase 3: Aggregate

Collect results from completed agents.

```bash
ppg aggregate --all --json
```

Returns:
```json
{
  "results": [
    {
      "agentId": "ag-xyz12345",
      "worktreeId": "wt-abc123",
      "worktreeName": "task-name",
      "branch": "ppg/task-name",
      "status": "completed",
      "content": "## Results\n\nThe agent's output from its result file..."
    }
  ]
}
```

**For swarm mode:**
- Read all results
- Identify common themes, agreements, and conflicts across agents
- Synthesize into a unified summary with attribution (which agent said what)
- Highlight any disagreements between agents

**For batch mode:**
- Present a table: task name | status | branch | brief summary of result
- For failed agents, show what went wrong
- Keep individual results available for the user to drill into

## Phase 4: Present Results

**Stop here and let the user decide.** Do NOT auto-merge or auto-PR.

**For swarm mode:**
- Present synthesized findings
- The output is advisory — typically no further action needed
- If agents made code changes, ask the user what to do with them

**For batch mode:**

Present a results table with PR links:
```
Completed:
  [1] fix-auth-bug (wt-abc123) — PR: https://github.com/org/repo/pull/42
  [2] add-dark-mode (wt-def456) — PR: https://github.com/org/repo/pull/43

Failed:
  [3] issue-15 (wt-ghi789) — no PR created

What would you like to do?
  - Review PRs on GitHub
  - Merge remotely: "gh pr merge <url> --squash --delete-branch"
  - Merge locally (power-user): "ppg merge <wt-id>"
  - Iterate: send more prompts to agents
  - Do nothing for now
```

**When the user chooses remote merge:**
```bash
gh pr merge <url> --squash --delete-branch
```

**When the user chooses local merge (power-user):**
```bash
ppg merge <wt-id> --json
```

**Merge conflict handling:**
- If `ppg merge` fails, capture the error
- Report the conflict to the user with: branch name, conflicting files if available
- Offer options: "resolve manually", "skip this merge", "force merge"
- **Never auto-resolve conflicts** — the user must decide

**Cleanup:**
```bash
ppg reset --json        # Skips worktrees with open PRs
ppg reset --force --json  # Force cleanup including open PRs
ppg clean --json        # Clean only terminal-state worktrees
```

## Phase 5: Summary

Present a final summary covering the entire run:

**For swarm mode:**
```
## Swarm Summary
- Subject: <what was reviewed/analyzed>
- Agents: N spawned, N completed, N failed
- Key findings: <synthesized highlights>
```

**For batch mode:**
```
## Batch Summary
- Tasks: N spawned, N completed, N failed
- Merged: N worktrees into <base-branch>
- Skipped: N (list reasons)
- PRs created: N (if applicable)
```

Include any follow-up actions the user might want to take.
