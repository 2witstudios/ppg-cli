# Feature Research Findings

---

## Agent 1: Missing Commands & Workflow Gaps

*Agent ID: `ag-6syyl6s6`*

# Result: ag-6syyl6s6

## Summary
Performed a comprehensive audit of the ppg-cli command set (10 commands across `src/cli.ts` and `src/commands/`) to identify missing commands, workflow gaps, error message quality, `--json` output consistency, and multi-step workflows that should be single commands.

## Changes
No files changed — this is a research/analysis deliverable.

## Audit Report: ppg-cli Command Gaps & Workflow Improvements

---

### Current Command Inventory

| Command | Description | `--json` | Watch |
|---------|-------------|----------|-------|
| `init` | Initialize `.pg/` structure | Yes | — |
| `spawn` | Create worktree + agent(s) | Yes | — |
| `status` | Show worktree/agent status | Yes | `-w` |
| `kill` | Kill agents/worktrees | Yes | — |
| `attach` | Attach to tmux pane | **No** | — |
| `logs` | View agent pane output | Yes | `-f` |
| `aggregate` | Collect agent results | Yes | — |
| `merge` | Merge worktree branch back | Yes | — |
| `list` | List templates | Yes | — |
| `ui` | Open native dashboard | **No** | — |

---

### P0 — High-Impact Missing Commands

#### 1. `ppg restart` — Restart Failed/Killed Agents

**Gap**: When an agent fails or is killed, there's no way to re-run it without manually reconstructing the spawn command. The worktree still exists, the prompt is saved in `.pg/prompts/{agentId}.md`, but you have to `ppg spawn --worktree <id> --prompt-file <path>` manually.

```
ppg restart <agent-id>
  --force              Restart even if agent is still running (kill first)
  --prompt <text>      Override the original prompt
  --prompt-file <path> Override with prompt from file
  --agent <type>       Change agent type
  --json               Output as JSON
```

**Implementation**: Read the original prompt from `.pg/prompts/{agentId}.md`, kill if running + `--force`, spawn a new agent in the same worktree with the same or overridden prompt. Update manifest to link new agent, mark old agent as `replaced`.

**Why P0**: Failed agents are the #1 workflow interruption. Conductor meta-agents need this to self-heal without human intervention.

---

#### 2. `ppg diff` — Show Agent Changes

**Gap**: No way to see what an agent has done without attaching to the worktree and running `git diff` manually. Critical for review-before-merge workflows.

```
ppg diff <worktree-id>
  --stat               Show diffstat only (like git diff --stat)
  --name-only          Show only changed file names
  --base               Diff against base branch (default) vs HEAD
  --json               Output as JSON
```

**Implementation**: Run `git diff <baseBranch>...<branch>` in the worktree directory. JSON output includes file list, additions, deletions, and optionally the full patch.

**Why P0**: Every merge should be preceded by a diff review. Conductors need this for automated review gates.

---

#### 3. `ppg clean` — Bulk Cleanup Stale Worktrees

**Gap**: After a session, you end up with merged/cleaned/failed worktrees cluttering the manifest and possibly orphaned git worktrees. `kill --all --remove` kills active agents but doesn't handle already-merged/failed ones cleanly. No way to prune the manifest.

```
ppg clean
  --merged             Remove only merged worktrees (default)
  --failed             Also remove failed worktrees
  --all                Remove all non-active worktrees
  --prune              Also run `git worktree prune`
  --dry-run            Show what would be removed
  --json               Output as JSON
```

**Implementation**: Filter manifest for worktrees in terminal states (`merged`, `cleaned`, `failed`). Kill any live tmux windows, teardown env, remove git worktree, delete branch, remove from manifest. Run `git worktree prune` if `--prune`.

**Why P0**: Manifest bloat makes `ppg status` noisy and confusing. No session cleanup = orphaned branches accumulate.

---

### P1 — Important Workflow Improvements

#### 4. `ppg send` — Send Instructions to Running Agents

**Gap**: Once an agent is running, the only way to interact is `ppg attach` + manual typing. No programmatic way to send follow-up instructions (e.g., "focus on file X" or "stop and write your result").

```
ppg send <agent-id> <text>
  --file <path>        Send contents of a file
  --ctrl-c             Send Ctrl-C before the message
  --enter              Press Enter after (default: true)
  --json               Output as JSON
```

**Implementation**: Wraps `tmux send-keys -t <target> -l "<text>"` + `send-keys Enter`. With `--ctrl-c`, sends `C-c` first then waits 500ms.

**Why P1**: Conductors need to redirect agents mid-task. Humans want to nudge without full attach/detach.

---

#### 5. `ppg retry` — Re-run a Worktree's Entire Task

**Gap**: Different from `restart` — this kills all agents in a worktree, optionally resets the branch, and spawns fresh agents. Useful when a whole task needs to start over.

```
ppg retry <worktree-id>
  --reset              git reset --hard to base branch before retry
  --prompt <text>      Override prompt
  --count <n>          Override agent count
  --json               Output as JSON
```

**Why P1**: Common scenario: agent went down a wrong path, need to reset and retry the whole worktree.

---

#### 6. `ppg config` — View/Edit Configuration

**Gap**: No command to inspect or modify `.pg/config.yaml`. Users must hand-edit YAML. `list` only supports `templates`, not agents/config.

```
ppg config
  ppg config get <key>           Show a config value
  ppg config set <key> <value>   Set a config value
  ppg config show                Show full config
  ppg config agents              List configured agent types
  --json                         Output as JSON
```

**Why P1**: Reduces friction for agent setup. `ppg config agents` is useful for discoverability.

---

#### 7. `ppg rename` — Rename Worktree

**Gap**: Worktree names are set at spawn time and immutable. A typo or unclear name means living with it forever (or killing + re-spawning).

```
ppg rename <worktree-id> <new-name>
  --json               Output as JSON
```

**Implementation**: Update `wt.name` in manifest, rename tmux window via `tmux rename-window`.

**Why P1**: Low-cost quality-of-life improvement. Manifest-only change + tmux rename.

---

### P2 — Nice-to-Have Commands

#### 8. `ppg history` — Session History

**Gap**: Once worktrees are cleaned, all record is lost. No history of past sessions, tasks, or outcomes.

```
ppg history
  --limit <n>          Show last N entries (default: 20)
  --status <status>    Filter by outcome (completed, failed, merged)
  --json               Output as JSON
```

**Implementation**: Append to `.pg/history.jsonl` on merge/clean/kill events. Each entry: `{worktreeId, name, branch, agents: [{id, status}], mergedAt, duration}`.

**Why P2**: Useful for understanding patterns, but not blocking any workflow.

---

#### 9. `ppg clone` — Clone Worktree Configuration

**Gap**: No way to duplicate a worktree's setup (same prompt, same agent type, same base) without re-typing all options.

```
ppg clone <worktree-id>
  --name <name>        New name (default: auto-generated)
  --base <branch>      Override base branch
  --json               Output as JSON
```

**Implementation**: Read the worktree entry + its agents' prompt files, spawn a new worktree with the same parameters.

**Why P2**: Useful for "run the same task again on a different base" or "spawn another copy."

---

#### 10. `ppg wait` — Block Until Agents Complete

**Gap**: Conductors must poll `ppg status --json` in a loop. A blocking `wait` command simplifies scripting.

```
ppg wait [worktree-id]
  --all                Wait for all agents
  --timeout <seconds>  Maximum wait time
  --poll <seconds>     Poll interval (default: 5)
  --json               Output final status as JSON
```

**Implementation**: Poll `refreshAllAgentStatuses()` every N seconds, exit 0 when all target agents are in terminal state, exit 1 on timeout.

**Why P2**: Simplifies conductor scripts from poll-loops to `ppg wait --all --json && ppg aggregate --all --json`.

---

### Workflow Gaps (Multi-Command Sequences That Should Be Easier)

#### A. "Review and Merge" Workflow
**Current**: `ppg status` → `ppg attach` → manual `git diff` → `ppg merge`
**Proposed**: `ppg diff <wt-id> --stat` fills the review gap. Alternatively, `ppg merge --preview` could show the diff before confirming.

#### B. "Retry Failed Agent" Workflow
**Current**: Note the agent's prompt → `ppg kill -a <id>` → `ppg spawn -w <wt-id> -p <prompt>`
**Proposed**: `ppg restart <agent-id>` does all three.

#### C. "Session Teardown" Workflow
**Current**: `ppg kill --all --remove` → orphaned manifest entries remain → manual manifest cleanup
**Proposed**: `ppg clean --all --prune` handles everything.

#### D. "Spawn Multiple Independent Tasks" Workflow
**Current**: Run `ppg spawn` N times sequentially.
**Proposed**: `ppg spawn --batch <tasks.yaml>` reads a YAML file with multiple task definitions and spawns them all. Lower priority but useful for conductor startup.

---

### Error Message Audit

Overall quality is **good**. Specific issues:

| Location | Issue | Recommendation |
|----------|-------|----------------|
| `spawn.ts:90` | `"One of --prompt, --prompt-file, or --template is required"` | Good, but should suggest: `ppg spawn --help` |
| `kill.ts:21` | `"One of --agent, --worktree, or --all is required"` | Add positional argument support: `ppg kill <id>` should auto-detect if it's an agent or worktree |
| `attach.ts:37` | `"Could not resolve target: ${target}. Try a worktree ID, name, or agent ID."` | Good — includes recovery hint |
| `list.ts:14` | `"Unknown list type: ${type}. Available: templates"` | Should expand as more types are added (agents, worktrees, config) |
| `merge.ts:42` | `"${incomplete.length} agent(s) still running: ${ids}. Use --force to merge anyway."` | Excellent — shows IDs and suggests flag |
| `logs.ts:53` | `"Pane no longer available"` written to stderr with `process.exit(1)` in follow mode | Should use `outputError()` for consistency. No `--json` handling in this error path |
| `config.ts:75` | `"Unknown agent type: ${agentName}. Available: ${...}"` | Good — lists alternatives |

**Missing error for common case**: When `ppg spawn` is run outside a git repo, `getRepoRoot()` throws `NotGitRepoError` but the message doesn't mention `ppg init`. Since both init + spawn require a git repo, this is fine, but a user running ppg for the first time might be confused.

---

### `--json` Output Consistency Audit

| Issue | Details |
|-------|---------|
| `attach` has no `--json` flag | Should support `--json` to output `{target, tmuxTarget}` for scripting |
| `ui` has no `--json` flag | Minor — less important for conductor use |
| `status --watch` with `--json` | Works but outputs multiple JSON objects separated by `console.clear()` — conductors would prefer NDJSON (one JSON object per line, no clearing) |
| `merge` JSON output only on success | If merge succeeds, JSON is printed. If it fails, the error is thrown as a plain Error (not PgError), so `outputError` doesn't get a proper code. Should be `PgError('Merge failed: ...', 'MERGE_FAILED')` |
| `kill` JSON shape varies | `killSingleAgent` returns `{killed: [id]}`, `killWorktreeAgents` returns `{killed: [...], removed: bool}`, `killAllAgents` returns `{killed: [...], removed: [...]}`. The `removed` field type is inconsistent (boolean vs array) |
| `aggregate` missing `worktreeId` in JSON | JSON output includes results but doesn't echo back which worktrees were aggregated |
| `spawn` JSON shape differs | New worktree spawn returns `{worktree: {id, name, branch, path, tmuxWindow}, agents}`. Existing worktree spawn returns `{worktree: {id, name}, agents}` — missing `branch`, `path`, `tmuxWindow`. Should be consistent |

---

### `list` Command Expansion

Currently `ppg list` only supports `templates`. Natural expansions:

```
ppg list agents        # List configured agent types from config.yaml
ppg list worktrees     # Alias for `ppg status` (or filtered view of non-active)
ppg list templates     # Existing
```

---

### Summary: Prioritized Recommendations

| Priority | Item | Effort | Impact |
|----------|------|--------|--------|
| **P0** | `ppg restart <agent-id>` | Medium | Unblocks self-healing conductor loops |
| **P0** | `ppg diff <worktree-id>` | Small | Enables review-before-merge |
| **P0** | `ppg clean` | Medium | Session hygiene, prevents manifest bloat |
| **P1** | `ppg send <agent-id> <text>` | Small | Enables mid-task agent redirection |
| **P1** | `ppg retry <worktree-id>` | Medium | Full-task restart with optional reset |
| **P1** | `ppg config` subcommands | Small | Discoverability, reduces hand-editing |
| **P1** | `ppg rename <wt-id> <name>` | Tiny | Quality of life |
| **P1** | Fix `--json` inconsistencies | Small | Conductor reliability |
| **P1** | Fix `kill` positional argument | Tiny | UX: `ppg kill ag-xxx` instead of `ppg kill -a ag-xxx` |
| **P2** | `ppg history` | Medium | Session retrospectives |
| **P2** | `ppg clone <worktree-id>` | Small | Duplicate task setups |
| **P2** | `ppg wait` | Small | Simplifies conductor scripting |
| **P2** | `ppg list agents/worktrees` | Tiny | Discoverability |
| **P2** | `ppg spawn --batch` | Medium | Bulk conductor startup |

## Notes

- The existing codebase is well-structured and consistent. Error handling follows a clear pattern with typed `PgError` hierarchy. The signal-stack status detection is solid.
- The biggest gap for conductor workflows is the restart/retry loop — agents fail, and there's no programmatic recovery path without reconstructing spawn commands.
- The `--json` inconsistencies are minor but will cause conductor scripts to need special-casing. Worth normalizing early before the API stabilizes.
- `ppg diff` is trivially implementable (just shell out to `git diff`) but adds enormous value to the review workflow.
- The `ppg send` command is essentially a thin wrapper around tmux but provides a clean abstraction for conductor mode.
- Consider adding a `ppg doctor` command (P2) that validates the manifest against actual git worktree/tmux state and repairs inconsistencies.



---

## Agent 2: Competitor Research & Feature Adoption

*Agent ID: `ag-r9sw40uy`*

# Result: ag-r9sw40uy

## Summary
Comprehensive competitive analysis of ppg-cli against 6 competitor tools (Nx, Turborepo, tmuxinator, Mprocs, Foreman/Overmind, Aider) plus 4 adjacent AI coding tools (Claude Code, Cursor, Codex CLI, Devin). Identified top 10 features ranked by strategic value, implementation complexity, and differentiation potential.

## Competitive Landscape Analysis

### ppg-cli's Current Position

ppg-cli occupies a unique niche: **a local orchestration runtime for parallel AI coding agents using git worktrees and tmux**. No single competitor covers this exact space. The tool combines:
- Git worktree isolation (unique to ppg-cli and Cursor 2.0 in the AI space)
- Tmux-based process management (shared with Overmind)
- Agent-agnostic configuration (unique — supports any CLI agent)
- Conductor mode for meta-agent orchestration (unique)
- JSON output on all commands for programmatic control (shared with Nx/Turborepo)
- Result file signaling and aggregation (unique)
- Template system for reusable prompts (unique in AI tool space)

### Competitor Summary Matrix

| Tool | Primary Domain | Parallelism Model | State Mgmt | AI-Aware |
|------|---------------|-------------------|------------|----------|
| **Nx** | Monorepo build orchestration | DAG-scheduled tasks across projects | In-memory + Nx Cloud | Yes (MCP, worktrees) |
| **Turborepo** | Monorepo task running | DAG-scheduled, single machine | Hash-based cache | No |
| **tmuxinator** | Tmux session bootstrap | Static window/pane layout | None (stateless) | No |
| **Mprocs** | TUI process runner | Concurrent processes in TUI | In-memory only | No |
| **Foreman/Overmind** | Procfile process mgmt | All processes run simultaneously | None / tmux windows | No |
| **Aider** | AI pair programming | Single-agent only | Git history | Deeply |
| **ppg-cli** | AI agent orchestration | Agents in isolated worktrees | Manifest JSON + tmux | Yes |

---

## Top 10 Feature Recommendations

### 1. Daemon Mode with Socket Control API
**Strategic Value: 10/10 | Complexity: High | Differentiation: 9/10**

**Inspiration:** Mprocs (TCP control), Overmind (Unix socket IPC)

**The Problem:** Every `ppg` CLI invocation incurs Node.js cold-start overhead (~300-500ms). A conductor polling `ppg status --json` every 5s spawns a new process each time. For tight orchestration loops with dozens of agents, this adds up.

**The Feature:** `ppg daemon` starts a background process listening on `.pg/ppg.sock` (Unix socket). All CLI commands (`spawn`, `status`, `kill`, `merge`) route through the socket when a daemon is running, achieving sub-50ms response times. The daemon also enables:
- Real-time event streaming (agent status changes pushed to subscribers)
- WebSocket bridge for dashboard integration
- Persistent in-memory state (no manifest re-read per operation)

**Implementation:**
```
ppg daemon start    # Start background daemon
ppg daemon stop     # Graceful shutdown
ppg daemon status   # Check if running
```
When the daemon is running, all other ppg commands auto-detect the socket and use it. Fallback to direct manifest access when no daemon.

**Why it matters:** This transforms ppg from a "cold CLI tool" into a "live orchestration runtime" — a prerequisite for sophisticated conductor patterns, real-time dashboards, and high-frequency polling.

---

### 2. Task DAG / Dependency Graph
**Strategic Value: 9/10 | Complexity: High | Differentiation: 10/10**

**Inspiration:** Nx (pipeline system), Turborepo (dependsOn)

**The Problem:** ppg-cli treats all spawned agents as independent. In reality, many conductor workflows have dependencies: "build the data layer, then build the API, then build the UI." Currently the conductor must manually sequence these, which is fragile and hard to express.

**The Feature:** A task graph declaration in config or at spawn time:

```yaml
# .pg/tasks/feature-auth.yaml
tasks:
  data-layer:
    prompt: "Implement user model and database schema"
    agent: claude
  api:
    prompt: "Build auth API endpoints"
    agent: claude
    dependsOn: [data-layer]
  ui:
    prompt: "Build login/signup UI"
    agent: claude
    dependsOn: [api]
  tests:
    prompt: "Write integration tests"
    agent: claude
    dependsOn: [api, ui]
```

```bash
ppg run feature-auth.yaml          # Execute the full DAG
ppg run feature-auth.yaml --graph  # Visualize the execution plan
ppg run feature-auth.yaml --dry    # Show what would run
```

ppg would automatically:
- Spawn independent tasks in parallel
- Wait for dependencies before spawning downstream tasks
- Propagate failures (dependent tasks marked `blocked`)
- Merge in topological order

**Why it matters:** This is the single biggest architectural leap ppg-cli could make. No AI agent orchestrator offers declarative task DAGs today. Nx and Turborepo proved this is the right abstraction for parallel work — ppg-cli would be first to apply it to AI agents.

---

### 3. Caching / Deduplication of Agent Results
**Strategic Value: 8/10 | Complexity: Medium | Differentiation: 8/10**

**Inspiration:** Nx (computation caching), Turborepo (content-addressable cache)

**The Problem:** If a conductor run fails halfway through and is restarted, all agents re-run from scratch — even the ones that completed successfully. For expensive LLM operations (each agent session can cost $0.50-$5.00), this is wasteful.

**The Feature:** Hash-based result caching:
- Input hash = hash(prompt_text + template_name + base_branch + agent_type)
- On spawn, check `.pg/cache/{hash}.md` for a cached result
- If cache hit, skip spawning and return cached result immediately
- `--no-cache` flag to force re-execution
- `ppg cache clear` to purge

```bash
ppg spawn --name auth --prompt "Build auth" --json
# First run: spawns agent, writes result, caches it
# Second run with same prompt: instant cache hit

ppg spawn --name auth --prompt "Build auth" --no-cache --json
# Forces re-execution
```

**Why it matters:** Reduces cost and time for iterative conductor workflows. When a conductor orchestrates 10 tasks and 3 fail, restarting only re-runs the 3 failures. This directly saves money on LLM API calls.

---

### 4. Auto-Restart with Crash Loop Protection
**Strategic Value: 8/10 | Complexity: Low | Differentiation: 7/10**

**Inspiration:** Overmind (`auto-restart`), Mprocs (`autorestart` with 1s guard)

**The Problem:** When an agent fails (e.g., API rate limit, transient error), the conductor must detect the failure, decide whether to retry, and manually respawn. This is boilerplate that every conductor must implement.

**The Feature:** Add `autoRestart` and `canDie` policies to agent configuration:

```yaml
# .pg/config.yaml
agents:
  claude:
    command: claude --dangerously-skip-permissions
    autoRestart: true       # Retry on failure
    maxRestarts: 3          # Cap retries
    restartDelay: 10        # Seconds between retries
    canDie: false           # Agent failure = worktree failure (default)
```

Implementation in `AgentEntry`:
```typescript
interface AgentEntry {
  // ... existing fields
  autoRestart?: boolean;
  maxRestarts?: number;
  restartCount?: number;
  canDie?: boolean;
}
```

**Crash loop guard:** If an agent fails within 30 seconds of spawning, do not restart (likely a config/permission error, not a transient failure).

**Why it matters:** Eliminates the most common conductor boilerplate. Makes ppg-cli resilient to transient failures without human intervention.

---

### 5. Passive Log Capture to Files
**Strategic Value: 7/10 | Complexity: Low | Differentiation: 6/10**

**Inspiration:** Mprocs (`log_dir`), Foreman (stdout multiplexing)

**The Problem:** When an agent fails, debugging requires attaching to the tmux pane (`ppg attach`) or reading the last N lines (`ppg logs`). If the tmux pane was killed or the session died, the output is lost. The result file only captures structured output, not the full agent stream.

**The Feature:** Automatically capture each agent's full tmux pane output to `.pg/logs/{agentId}.log`:

```bash
# Automatic — runs in background via tmux pipe-pane
ppg spawn --name auth --prompt "..."
# → .pg/logs/ag-abc12345.log created automatically

# Manual review
ppg logs ag-abc12345 --file    # Read from log file instead of live pane
```

Implementation: Use tmux's `pipe-pane -o` command to tee pane output to a file immediately after agent spawn. This captures everything regardless of pane lifecycle.

**Why it matters:** Post-mortem debugging of failed agents becomes trivial. Log files persist even after worktree cleanup. Essential for auditing and improving prompts.

---

### 6. Pre-Spawn Hooks and Agent Pre-Commands
**Strategic Value: 7/10 | Complexity: Low | Differentiation: 5/10**

**Inspiration:** tmuxinator (`on_project_start`, `pre_window`), Overmind (env layering)

**The Problem:** Some workflows need setup before agents run: starting Docker containers, building dependencies, activating virtual environments. Currently this must be baked into the agent prompt or done manually.

**The Feature:** Lifecycle hooks in config:

```yaml
# .pg/config.yaml
hooks:
  onSessionStart: docker-compose up -d    # Once when ppg init / first spawn
  onWorktreeCreate: npm install           # After git worktree add
  onAgentComplete: notify-send "Done"     # After result file detected
  onAllComplete: ppg aggregate --all      # After all agents complete

agents:
  claude:
    preCommand: source .venv/bin/activate  # Runs in pane before agent command
    stopSignal: SIGINT                     # How to terminate (vs default Ctrl-C)
```

**Why it matters:** Eliminates manual setup steps. Makes ppg-cli self-contained for complex project environments (Docker, virtualenvs, build steps). The `onAllComplete` hook enables fully autonomous conductor-free workflows.

---

### 7. Affected Analysis / Smart Re-runs
**Strategic Value: 7/10 | Complexity: Medium | Differentiation: 8/10**

**Inspiration:** Nx (`affected`), Turborepo (`--affected`)

**The Problem:** When re-running a conductor workflow after partial completion, all tasks are re-evaluated. There's no way to ask "which of my previous agent results are still valid given what changed?"

**The Feature:** Track which files each agent modified and use git diff to determine if cached results are still valid:

```bash
ppg affected --base main
# → Lists worktrees whose base branch has changed since their agent ran

ppg spawn --affected --template feature
# → Only spawns agents for tasks affected by recent changes

ppg rerun --failed
# → Re-spawns only failed agents with the same prompt
```

Implementation:
- After merge, record the list of files changed per worktree in the manifest
- On `ppg affected`, compare `git diff --name-only base..HEAD` against recorded file lists
- Intersections indicate stale results that need re-running

**Why it matters:** Prevents unnecessary re-work in iterative workflows. Especially valuable when a conductor is refining a large feature across multiple runs.

---

### 8. Repomap / Codebase Context Generation
**Strategic Value: 6/10 | Complexity: Medium | Differentiation: 7/10**

**Inspiration:** Aider (PageRank-based repomap), Nx (project graph for AI)

**The Problem:** When spawning an agent on a sub-task, the agent lacks context about the overall codebase structure. It must explore autonomously, which wastes tokens and time. A conductor can partially address this by including context in prompts, but this is manual and inconsistent.

**The Feature:** `ppg context` generates a compact structural map of the codebase:

```bash
ppg context > .pg/context.md
# Generates a tree-sitter-based outline of the codebase

ppg spawn --name auth --prompt "Build auth" --context
# Automatically prepends context.md to the agent's prompt
```

The context could include:
- Directory tree with file descriptions
- Key type/interface definitions
- Export graph (what depends on what)
- CLAUDE.md / README content

A `--context` flag on `ppg spawn` would automatically include this in the agent prompt, giving every agent a shared understanding of the codebase without the conductor having to manually curate context.

**Why it matters:** Improves agent output quality by reducing "cold start" exploration. Especially valuable for agents working on tasks that touch multiple modules.

---

### 9. Interactive TUI Dashboard
**Strategic Value: 6/10 | Complexity: Medium | Differentiation: 6/10**

**Inspiration:** Mprocs (full TUI), Nx 21 (Rust-based terminal UI), Turborepo 2.0 (interactive TUI)

**The Problem:** ppg-cli has a native macOS Swift dashboard, but it's platform-specific. `ppg status --watch` provides live updates but in a flat table format. There's no cross-platform interactive terminal UI.

**The Feature:** `ppg tui` launches an interactive terminal dashboard:

```
┌─ Agents ────────────────┬─ Output ──────────────────────────────┐
│ ● auth-api     running  │ [ag-abc12345] claude                  │
│ ✓ data-model completed  │                                       │
│ ✗ ui-login    failed    │ Reading src/auth/routes.ts...          │
│ ○ tests       pending   │ I'll implement the login endpoint     │
│                         │ with JWT token validation...           │
│                         │                                       │
│ [s]pawn [k]ill [a]ttach │ Writing src/auth/login.ts...          │
│ [m]erge [r]estart [q]uit│                                       │
└─────────────────────────┴───────────────────────────────────────┘
```

Features:
- Left panel: agent list with real-time status
- Right panel: live tmux pane output for selected agent
- Keyboard shortcuts for common operations
- Works on any terminal (not macOS-only)

Implementation: Use a Rust or Node.js TUI library (e.g., `ink` for Node, `ratatui` for Rust). Poll manifest + tmux pane output on a timer.

**Why it matters:** Makes ppg-cli accessible on Linux and in SSH sessions. Provides a "single pane of glass" without needing tmux knowledge. The Mprocs/Nx TUI pattern has proven popular.

---

### 10. Formation / Batch Spawn from Config
**Strategic Value: 5/10 | Complexity: Low | Differentiation: 5/10**

**Inspiration:** Overmind (`-m web=2,worker=3`), tmuxinator (declarative layouts)

**The Problem:** Spawning multiple agents requires multiple `ppg spawn` commands or a conductor script. For common patterns (e.g., "3 Claude agents on this template"), there's no declarative shorthand.

**The Feature:** Define formations in config:

```yaml
# .pg/formations/review-swarm.yaml
name: Code Review Swarm
base: main
agents:
  - name: security-review
    agent: claude
    template: security-audit
    vars:
      FOCUS: "OWASP top 10"
  - name: perf-review
    agent: claude
    template: perf-audit
  - name: style-review
    agent: claude
    template: style-check
```

```bash
ppg formation review-swarm
# Spawns all 3 agents in one command, each in its own worktree
```

This is essentially a higher-level orchestration primitive — one step above `ppg spawn` but below a full conductor. It's the "Procfile for AI agents."

**Why it matters:** Reduces boilerplate for common multi-agent patterns. Makes ppg-cli more approachable for users who don't want to write conductor scripts.

---

## Feature Ranking Summary

| Rank | Feature | Strategic Value | Complexity | Differentiation | Priority Score |
|------|---------|:-:|:-:|:-:|:-:|
| 1 | Task DAG / Dependency Graph | 9 | High | 10 | **29** |
| 2 | Daemon Mode + Socket API | 10 | High | 9 | **29** |
| 3 | Caching / Deduplication | 8 | Medium | 8 | **26** |
| 4 | Auto-Restart + Crash Guard | 8 | Low | 7 | **25** |
| 5 | Affected Analysis | 7 | Medium | 8 | **25** |
| 6 | Pre-Spawn Hooks | 7 | Low | 5 | **22** |
| 7 | Passive Log Capture | 7 | Low | 6 | **22** |
| 8 | Repomap Context Generation | 6 | Medium | 7 | **22** |
| 9 | Interactive TUI Dashboard | 6 | Medium | 6 | **21** |
| 10 | Formation / Batch Spawn | 5 | Low | 5 | **20** |

*Priority Score = Strategic Value + (10 - Complexity_numeric) + Differentiation, where Low=2, Medium=5, High=8*

---

## Implementation Roadmap Recommendation

### Phase 1: Quick Wins (Low complexity, high value)
1. **Auto-Restart with Crash Guard** — add `autoRestart`, `maxRestarts`, `canDie` to AgentConfig
2. **Passive Log Capture** — add `pipe-pane` after spawn in `agent.ts`
3. **Pre-Spawn Hooks** — add `preCommand` to AgentConfig, `hooks` to Config

### Phase 2: Core Architecture (High value, medium complexity)
4. **Caching / Deduplication** — hash-based result cache in `.pg/cache/`
5. **Formation / Batch Spawn** — YAML formation files, `ppg formation` command
6. **Affected Analysis** — file tracking per worktree, `ppg affected` command

### Phase 3: Platform Leap (High complexity, transformative)
7. **Daemon Mode + Socket API** — Unix socket server, auto-detect in CLI
8. **Task DAG** — YAML task graph, `ppg run` command, topological scheduling

### Phase 4: Experience Polish
9. **Repomap Context** — tree-sitter integration, `ppg context` command
10. **Interactive TUI** — cross-platform terminal dashboard

---

## Strategic Observations

### ppg-cli's Moat
The combination of **git worktree isolation + tmux process management + agent-agnostic config + conductor mode** is unique in the market. No tool — not Nx, not Cursor, not Aider — provides this exact combination as an open-source CLI. The closest competitor is Cursor 2.0's parallel agents, but that's locked inside a proprietary IDE.

### Convergence Signal
Both Nx and Cursor have independently converged on git worktrees as the right isolation primitive for AI agents. Nx's blog explicitly describes the same pattern ppg-cli implements. This validates ppg-cli's architectural choice.

### The Nx Threat
Nx is the most significant competitive threat. They are actively building:
- MCP server for AI agent integration
- Git worktree-based AI workflows
- "Synthetic monorepo" for multi-repo orchestration
- Claude Code plugin for workspace context

If Nx ships a first-class `nx ai:spawn` command with worktree isolation and DAG scheduling, it would overlap significantly with ppg-cli's value proposition. ppg-cli should differentiate by being **simpler, CLI-first, and agent-agnostic** — Nx is always going to be a heavyweight monorepo tool.

### The "Conductor Protocol" Opportunity
ppg-cli's `--json` output on all commands creates a de facto API for conductor agents. Formalizing this as a documented protocol (input commands → JSON responses → status polling → result aggregation) would make ppg-cli the standard orchestration layer for any AI agent system. This is a bigger opportunity than any single feature.

## Changes
No code changes — research-only task.

## Notes
- Nx is actively building AI + worktree features that overlap with ppg-cli's niche. Monitor their roadmap closely.
- The daemon + socket API (Feature #2) is a prerequisite for Features #1 (DAG) and #7 (Affected) to work efficiently.
- Auto-restart (Feature #4) and passive logging (Feature #5) are the cheapest wins with immediate user value.
- The "Formation" concept (Feature #10) could be a stepping stone toward the full DAG feature (#1) — start with flat formation files, then add `dependsOn` later.
- Cursor 2.0's parallel agents feature validates the entire ppg-cli thesis — users want worktree-isolated parallel AI agents.



---

## Agent 3: Conductor/Orchestration Improvements

*Agent ID: `ag-390yf24y`*

# Result: ag-390yf24y

## Summary
Comprehensive analysis of ppg-cli's conductor/orchestration mode. Evaluated the full spawn-poll-aggregate-merge loop across all source files, identified architectural gaps, and designed a v2 orchestration vision covering DAGs, auto-retry, streaming, workflow YAML, and more.

## Changes
No code changes — this is a research/analysis report only.

## Notes

---

# ppg-cli Conductor Orchestration Analysis

## 1. Current Architecture Assessment

### 1.1 The Primitives

ppg provides five orchestration primitives that a conductor uses sequentially:

| Primitive | Command | JSON Output | Purpose |
|-----------|---------|-------------|---------|
| **Spawn** | `ppg spawn --name <n> --prompt <p> --json` | `{ worktree.id, agents[].id }` | Create isolated worktree + agent(s) |
| **Poll** | `ppg status --json` | `{ worktrees.*.agents.*.status }` | Detect completion via signal stack |
| **Aggregate** | `ppg aggregate --all --json` | `{ results[].content }` | Collect result files |
| **Merge** | `ppg merge <wt-id> --json` | `{ success, strategy }` | Squash/no-ff merge back to base |
| **Kill** | `ppg kill --worktree <id> --json` | `{ killed[], removed }` | Terminate agents, cleanup |

### 1.2 What Works Well

**Signal-stack status detection** (`core/agent.ts:89-133`) is the strongest design decision. The layered priority system (result file → pane exists → pane dead → current command → running) provides reliable status without IPC, agent cooperation, or heartbeats. This is fundamentally sound.

**Manifest-based state** with file locking (`core/manifest.ts:32-63`) provides safe concurrent access. The `updateManifest(projectRoot, updater)` pattern with `proper-lockfile` (10s stale, 5 retries) and `write-file-atomic` is correct for the single-host model.

**Template system** (`core/template.ts`) with `{{VAR}}` substitution gives conductors parameterized prompts without complex DSLs.

**Agent-agnostic design** — the `AgentConfig` type (`types/config.ts`) abstracts over different CLI agents, making ppg work with Claude Code, Codex, or custom scripts equally.

**Dual output** — every command supports `--json`, making machine consumption reliable.

### 1.3 The Conductor Loop Today

A conductor currently must implement this loop itself (typically as a meta-agent prompt):

```
1. Plan tasks (in the conductor's own logic)
2. for each task:
     ppg spawn --name <name> --prompt <task> --json
3. loop:
     ppg status --json
     if all agents completed/failed: break
     sleep 5s
4. ppg aggregate --all --json
5. for each completed worktree:
     ppg merge <wt-id> --json
```

This works but has significant limitations.

---

## 2. Gap Analysis

### 2.1 No Task Dependencies / DAG Support

**Current state:** All spawned tasks are fully independent. There's no way to express "task B depends on task A's output" or "task C starts only after A and B finish."

**Impact:** Conductors that need multi-stage pipelines (e.g., "generate API → generate tests → generate docs") must implement all dependency tracking themselves, including:
- Maintaining a dependency graph
- Watching for specific completions
- Passing outputs between stages
- Handling partial failures in the graph

**Evidence:** `spawn.ts` has no `dependsOn`, `after`, or `waitFor` parameter. `WorktreeEntry` and `AgentEntry` types have no dependency fields.

### 2.2 No Conditional Spawning

**Current state:** Every spawn is unconditional. There's no "spawn B only if A succeeds" or "spawn B with A's result as input."

**Impact:** Multi-phase workflows require the conductor to manually:
1. Wait for phase 1
2. Read results
3. Decide whether to proceed
4. Construct new prompts incorporating previous results
5. Spawn phase 2

This is entirely the conductor's responsibility — ppg provides no help.

### 2.3 No Auto-Retry

**Current state:** When an agent fails (`status: "failed"`), it stays failed. The conductor must detect the failure, decide to retry, kill/cleanup the failed worktree, and re-spawn.

**Evidence:** `checkAgentStatus()` transitions to `failed` terminal state with no retry logic. No `maxRetries`, `retryCount`, or `retryDelay` in `AgentEntry` or `SpawnOptions`.

**Impact:** Transient failures (agent timeout, LLM rate limiting, temporary network issues) permanently fail the task. Conductors need ~20 lines of retry boilerplate per task.

### 2.4 Polling-Only Progress Model

**Current state:** `ppg status --watch` polls every 2 seconds (`status.ts:55-80`). JSON status requires manual polling. No events, no callbacks, no file watching.

**Impact:**
- Conductors waste cycles polling when nothing has changed
- 2-second minimum latency between completion and detection
- No way to get notified of intermediate progress (e.g., "agent wrote 3 files so far")
- Watch mode clears the screen (`console.clear()`) — not composable

### 2.5 No Streaming Aggregation

**Current state:** `aggregateCommand()` reads result files only after agents are in `completed` or `failed` status. The `collectAgentResult()` function (`aggregate.ts:111-130`) reads the result file or falls back to pane capture.

**Impact:** For long-running agents, the conductor gets zero intermediate results. You can't stream partial results, inspect progress, or build incremental summaries.

### 2.6 No Workflow Definitions

**Current state:** Workflows live entirely in the conductor's prompt or script. There's no declarative workflow file.

**Impact:**
- Workflows aren't reproducible across conductor invocations
- No way to version-control a multi-stage orchestration pattern
- Conductors must re-plan the same workflow each time
- No workflow visualization or validation

### 2.7 No Result Validation

**Current state:** Agent results are opaque markdown files. `aggregate.ts` concatenates them without any validation.

**Impact:**
- No way to verify an agent actually did what was asked
- No structured result parsing (just raw markdown)
- A "completed" agent might have written garbage to its result file
- No schema validation, no checksums, no quality gates

### 2.8 No Resource Limits

**Current state:** You can spawn unlimited agents. No concurrency cap, no memory awareness, no CPU limit, no worktree cap.

**Evidence:** `spawnCommand()` has no concurrency checking. No `maxConcurrent` in config. No system resource inspection.

**Impact:** A conductor that spawns 20 Claude Code agents simultaneously will likely exhaust system resources (memory, CPU, API rate limits). No backpressure mechanism.

### 2.9 No Map-Reduce / Fan-out-Fan-in Patterns

**Current state:** Fan-out is manual (multiple `ppg spawn` calls). Fan-in is manual (`ppg aggregate`). There's no built-in "spawn N agents with the same template but different inputs, then combine results."

**Impact:** The most common conductor pattern (parallelize a task across N inputs) requires the conductor to implement the entire fan-out, tracking, and fan-in logic.

### 2.10 No Pipeline Concept

**Current state:** Each spawn creates an isolated worktree. There's no concept of a pipeline where output from stage 1 flows into stage 2's worktree.

**Impact:** Multi-stage workflows can't share filesystem state between stages without the conductor manually orchestrating file copies or branch merges between stages.

---

## 3. V2 Orchestration Vision

### 3.1 Workflow YAML Definition

Add `.pg/workflows/` directory. Workflows are declarative YAML:

```yaml
# .pg/workflows/feature-pipeline.yaml
name: feature-pipeline
description: Build, test, and document a feature
concurrency: 3

inputs:
  feature_description: string
  target_module: string

stages:
  implement:
    agent: claude
    template: implement-feature
    vars:
      DESCRIPTION: "{{inputs.feature_description}}"
      MODULE: "{{inputs.target_module}}"

  test:
    agent: claude
    template: write-tests
    depends_on: [implement]
    condition: "{{stages.implement.status == 'completed'}}"
    vars:
      BRANCH: "{{stages.implement.branch}}"
      CHANGES: "{{stages.implement.result}}"

  docs:
    agent: claude
    template: write-docs
    depends_on: [implement]
    vars:
      CHANGES: "{{stages.implement.result}}"

  review:
    agent: claude
    template: code-review
    depends_on: [test, docs]
    vars:
      IMPL_BRANCH: "{{stages.implement.branch}}"
      TEST_BRANCH: "{{stages.test.branch}}"
      DOC_BRANCH: "{{stages.docs.branch}}"
```

New command: `ppg run <workflow> --var feature_description="Add auth" --json`

**Implementation approach:** Add `src/core/workflow.ts` that parses YAML, builds a DAG, and drives the spawn-poll-merge loop internally. The workflow engine would use the existing primitives (`spawnCommand`, `statusCommand`, etc.) but add the sequencing layer.

### 3.2 DAG Execution Engine

Add a DAG scheduler to `src/core/dag.ts`:

```typescript
interface DagNode {
  id: string;
  dependsOn: string[];        // node IDs
  condition?: string;          // expression evaluated at runtime
  status: 'pending' | 'ready' | 'running' | 'completed' | 'failed' | 'skipped';
  worktreeId?: string;
  agentId?: string;
  result?: string;
  retryCount: number;
  maxRetries: number;
}

interface Dag {
  id: string;
  nodes: Record<string, DagNode>;
  status: 'running' | 'completed' | 'failed';
}
```

**Scheduler loop:**
1. Find all nodes where `dependsOn` are all `completed` and `condition` evaluates true → mark `ready`
2. Spawn `ready` nodes up to `concurrency` limit
3. Poll running nodes
4. On completion: update node, check if new nodes become `ready`
5. On failure: check `maxRetries`, re-spawn or mark `failed`
6. If any `failed` node blocks downstream → mark downstream `skipped`
7. When all nodes are terminal → DAG is `completed` or `failed`

### 3.3 Auto-Retry with Backoff

Add retry configuration at three levels:

```yaml
# Global default in config.yaml
retry:
  maxRetries: 2
  backoff: exponential  # linear, exponential, fixed
  initialDelay: 10s
  maxDelay: 120s

# Per-workflow override
stages:
  flaky-task:
    retry:
      maxRetries: 3
```

**Manifest changes:**

```typescript
interface AgentEntry {
  // ... existing fields
  retryCount?: number;
  maxRetries?: number;
  previousAttempts?: Array<{
    agentId: string;
    status: AgentStatus;
    error?: string;
    duration: number;
  }>;
}
```

**Implementation:** In the DAG scheduler, when a node transitions to `failed` and `retryCount < maxRetries`, create a new worktree+agent with the same prompt. The old worktree is cleaned up. The `previousAttempts` array provides debugging context.

### 3.4 Event-Driven Progress (Replace Polling)

Replace the poll loop with `fs.watch` on the results directory + tmux hooks:

```typescript
// core/events.ts
type PpgEvent =
  | { type: 'agent:completed'; agentId: string; worktreeId: string; resultPath: string }
  | { type: 'agent:failed'; agentId: string; worktreeId: string; exitCode?: number }
  | { type: 'agent:lost'; agentId: string; worktreeId: string }
  | { type: 'agent:progress'; agentId: string; data: unknown }
  | { type: 'workflow:stage_complete'; workflowId: string; stageId: string }
  | { type: 'workflow:complete'; workflowId: string };

interface EventEmitter {
  on(event: string, handler: (e: PpgEvent) => void): void;
  off(event: string, handler: (e: PpgEvent) => void): void;
}
```

**Three event sources:**
1. **`fs.watch` on `.pg/results/`** — instant detection of result file creation (agent completion)
2. **tmux `pane-died` hook** — `tmux set-hook -g pane-died 'run-shell "ppg _notify pane-died %P"'`
3. **`ppg status --stream`** — new flag that emits NDJSON events on stdout instead of a single snapshot

New command variant:
```
ppg status --stream  →  {"type":"agent:completed","agentId":"ag-abc12345","worktreeId":"wt-xyz123","time":"..."}
```

This replaces polling with push-based notification, reducing latency from 2s to ~50ms.

### 3.5 Streaming Aggregation

Add `ppg aggregate --stream` that watches for results as they arrive:

```
ppg aggregate --stream --json
→ {"event":"result","agentId":"ag-abc","worktreeId":"wt-xyz","content":"..."}
→ {"event":"result","agentId":"ag-def","worktreeId":"wt-uvw","content":"..."}
→ {"event":"complete","total":3,"collected":3}
```

Also add incremental progress capture:

```
ppg logs <agent-id> --follow --json
→ {"line":"Working on auth module...","time":"..."}
→ {"line":"Created 3 files...","time":"..."}
```

This lets conductors build incremental summaries and react to partial results.

### 3.6 Result Validation

Add optional result schema validation:

```yaml
# In workflow or agent config
resultSchema:
  required_sections: [Summary, Changes]
  max_length: 50000
  must_contain: ["## Summary", "## Changes"]
  custom_validator: ".pg/validators/check-result.sh"
```

```typescript
// core/validation.ts
interface ResultValidation {
  valid: boolean;
  errors: string[];
  warnings: string[];
  sections: Record<string, string>;  // parsed markdown sections
}

function validateResult(content: string, schema: ResultSchema): ResultValidation;
```

**On validation failure:** The agent status transitions to `failed` with `error: "result_validation_failed"`, triggering retry if configured.

Additionally, add **structured result parsing** that extracts the standard sections (Summary, Changes, Notes) into a machine-readable format in the aggregate JSON output.

### 3.7 Resource Limits and Backpressure

Add resource management to config:

```yaml
# config.yaml
resources:
  maxConcurrentAgents: 4
  maxWorktrees: 10
  maxAgentsPerWorktree: 3
  queueOverflow: reject  # reject | wait
```

```typescript
// core/scheduler.ts
interface ResourcePool {
  maxConcurrent: number;
  running: number;
  queued: DagNode[];

  acquire(): Promise<void>;  // blocks if at limit
  release(): void;
}
```

The scheduler respects the concurrency limit. When `running >= maxConcurrentAgents`, new spawns are queued. When an agent completes, the next queued node is spawned. This prevents resource exhaustion without conductor awareness.

### 3.8 Map-Reduce Pattern

Add a first-class `ppg map` command:

```bash
ppg map --template code-review \
  --inputs inputs.json \
  --concurrency 3 \
  --reduce .pg/templates/summarize.md \
  --json
```

Where `inputs.json` is:

```json
[
  {"FILE": "src/auth.ts", "TASK": "Review auth module"},
  {"FILE": "src/db.ts", "TASK": "Review database module"},
  {"FILE": "src/api.ts", "TASK": "Review API module"}
]
```

**Semantics:**
1. **Map phase:** For each input object, spawn one worktree with the template + input vars
2. **Wait:** Poll until all map agents complete (with retry)
3. **Reduce phase:** Aggregate all results, optionally spawn a final "reduce" agent with the combined output
4. **Output:** Combined results or reduce agent's result

In workflow YAML:

```yaml
stages:
  review-all:
    type: map
    template: code-review
    inputs: "{{computed_file_list}}"
    concurrency: 3

  summarize:
    type: reduce
    depends_on: [review-all]
    template: summarize-reviews
    vars:
      REVIEWS: "{{stages.review-all.results}}"
```

### 3.9 Pipeline / Stage Chaining

Add the concept of **pipeline stages** where each stage can access the previous stage's worktree state:

```yaml
stages:
  implement:
    agent: claude
    template: implement

  test:
    agent: claude
    template: test
    depends_on: [implement]
    base: "{{stages.implement.branch}}"  # Branch from implement's worktree
```

The key insight: `base: "{{stages.implement.branch}}"` means the test stage's worktree is branched off the implementation branch, giving it access to all the implementation's file changes without a merge step.

**Implementation:** In the DAG scheduler, when resolving a node's `base` field, look up the referenced stage's worktree entry and use its branch name as the base for `git worktree add`.

### 3.10 Fan-Out / Fan-In Pattern

Generalize the map-reduce pattern for dynamic fan-out:

```yaml
stages:
  plan:
    template: plan-tasks
    # Agent outputs a JSON array of sub-tasks in its result file

  execute:
    type: fan-out
    depends_on: [plan]
    source: "{{stages.plan.result | parse_tasks}}"
    template: execute-task
    concurrency: 4

  integrate:
    type: fan-in
    depends_on: [execute]
    template: integrate-results
    vars:
      ALL_RESULTS: "{{stages.execute.results}}"
```

**Fan-out semantics:** The `plan` stage produces a dynamic list of tasks. The `execute` stage spawns one agent per task from that list. The `integrate` stage runs once all fan-out agents complete.

**Implementation complexity:** This requires the workflow engine to parse agent results at runtime to determine how many fan-out nodes to create. A `parse_tasks` filter would extract a JSON array from the result markdown.

---

## 4. Implementation Priority

### Phase 1: Foundation (High Value, Low Risk)
1. **Resource limits** — `maxConcurrentAgents` in config, checked in `spawnCommand()`. Simple guard, prevents runaway conductors.
2. **Auto-retry** — Add `--retries <n>` to `ppg spawn`. On failure detection, re-spawn. ~100 lines of code.
3. **Result validation** — Parse standard sections from result markdown. Add `--validate` to `ppg aggregate`. ~50 lines.
4. **`ppg status --stream`** — NDJSON event stream using `fs.watch` on results directory. Huge conductor ergonomics win.

### Phase 2: Orchestration Layer (High Value, Medium Risk)
5. **Workflow YAML parser** — `src/core/workflow.ts`, parse `.pg/workflows/*.yaml`
6. **DAG scheduler** — `src/core/dag.ts`, topological sort + concurrent execution within limits
7. **`ppg run <workflow>`** — New command that drives the DAG scheduler
8. **Pipeline stage chaining** — `base: "{{stages.X.branch}}"` resolution in DAG nodes

### Phase 3: Advanced Patterns (Medium Value, Higher Risk)
9. **`ppg map` command** — Built on DAG scheduler + template system
10. **Fan-out / fan-in** — Dynamic node creation from result parsing
11. **Streaming aggregation** — `ppg aggregate --stream`
12. **Conditional expressions** — Expression evaluator for `condition` fields

### Non-Goals for V2
- **Remote/distributed execution** — Stay local. The tmux+worktree model is ppg's strength.
- **Persistent workflow state across restarts** — Workflows are ephemeral. If ppg dies, re-run.
- **Complex expression language** — Keep conditions simple (status checks, exists checks). No Turing-complete DSL.
- **Agent communication** — Agents don't talk to each other. All data flows through result files and the conductor.

---

## 5. Specific Code-Level Recommendations

### 5.1 `spawn.ts` — Add dependency tracking
Currently `SpawnOptions` has no dependency fields. Add:
```typescript
interface SpawnOptions {
  // ... existing
  dependsOn?: string[];    // worktree IDs to wait for
  retries?: number;        // max retry count
  tag?: string;            // for grouping in map operations
}
```

### 5.2 `manifest.ts` — Add workflow state
```typescript
interface Manifest {
  // ... existing
  workflows?: Record<string, WorkflowState>;
  resourceLimits?: { maxConcurrentAgents: number };
}

interface WorkflowState {
  id: string;
  name: string;
  status: 'running' | 'completed' | 'failed';
  dag: Record<string, DagNodeState>;
  startedAt: string;
  completedAt?: string;
}
```

### 5.3 `agent.ts` — Add retry metadata
```typescript
interface AgentEntry {
  // ... existing
  retryCount?: number;
  maxRetries?: number;
  workflowId?: string;
  stageId?: string;
  tags?: string[];
}
```

### 5.4 `status.ts` — Add event streaming
Add `--stream` flag that uses `fs.watch` instead of `setInterval`:
```typescript
if (options?.stream) {
  const watcher = fs.watch(resultsDir(projectRoot));
  // Emit NDJSON events on result file creation
}
```

### 5.5 `aggregate.ts` — Add structured parsing
```typescript
function parseResultSections(content: string): Record<string, string> {
  // Parse ## Summary, ## Changes, ## Notes sections
  // Return structured object instead of raw markdown
}
```

---

## 6. Conclusion

ppg's v1 orchestration primitives are **solid and well-designed** for the flat fan-out use case: spawn N independent agents, poll for completion, aggregate results, merge. The signal-stack status detection, manifest locking, and agent-agnostic design are genuinely good engineering.

The gaps are all in the **orchestration logic layer** above these primitives:
- No dependency graphs → conductors must implement their own DAG scheduling
- No retries → transient failures require manual intervention
- No resource limits → easy to exhaust system resources
- Polling-only → unnecessary latency and wasted cycles
- No declarative workflows → orchestration knowledge lives only in conductor prompts

The v2 vision adds this orchestration layer **on top of** the existing primitives, not replacing them. A `ppg run` command drives the DAG scheduler, which calls `ppg spawn`, `ppg status`, `ppg aggregate`, and `ppg merge` internally. Everything remains composable — conductors can still use raw primitives for simple cases, or use `ppg run` for complex multi-stage workflows.

The recommended implementation order (resource limits → auto-retry → event streaming → workflow YAML → DAG engine) delivers incremental value at each step, with each phase building on the previous one.


