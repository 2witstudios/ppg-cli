# Conductor Modes

## Swarm Mode — Multiple Agents, One Worktree

**Trigger signals:** "review", "audit", "analyze", "perspectives", "opinions", "critique", "evaluate", "assess", "examine", "check from multiple angles"

**Concept:** Multiple agents work on the SAME codebase in the SAME worktree. Each agent brings a different perspective or focus area. Their outputs are aggregated and synthesized — no merge needed because they produce analysis, not code changes.

**Task decomposition:**
1. Identify the subject (PR, file, module, system)
2. Define N perspectives — each gets a unique angle and prompt
3. Each prompt should specify: what to focus on, what format to produce results in, and what the result file should contain

**Spawn patterns:**

Option A — **Swarm template** (preferred when a matching template exists):
```
# Check available swarm templates
ppg list swarms --json

# Run a predefined swarm
ppg swarm code-review --var CONTEXT="Review the auth module" --json --no-open

# Run against an existing worktree
ppg swarm code-review --worktree <wt-id> --var CONTEXT="Review PR #42" --json --no-open
```

Option B — Single spawn with `--count` (same prompt, N agents):
```
ppg spawn --name "security-review" --prompt "Review for security vulnerabilities..." --count 3 --json --no-open
```

Option C — Sequential spawns into same worktree (different prompts per agent):
```
# First spawn creates the worktree
ppg spawn --name "pr-review" --prompt "Review code quality and readability..." --json --no-open
# Capture worktree ID from JSON output, then:
ppg spawn --worktree <wt-id> --prompt "Review for performance issues..." --json --no-open
ppg spawn --worktree <wt-id> --prompt "Review test coverage gaps..." --json --no-open
```

**Option A is preferred** when a matching swarm template exists. **Option C is preferred** for custom swarm workflows where each agent needs a distinct prompt.

**Post-completion:**
1. Aggregate all results: `ppg aggregate --all --json`
2. Synthesize findings — identify common themes, conflicts, and unique insights
3. Present a unified summary to the user
4. Typically NO merge — swarm output is advisory. If agents did make code changes, ask the user before merging.

**Suggested swarm sizes:**
- Code review: 3-4 agents (quality, security, performance, testing)
- Architecture review: 3 agents (design patterns, scalability, maintainability)
- Bug hunt: 2-3 agents (different hypotheses about root cause)

## Batch Mode — One Worktree Per Task

**Trigger signals:** "issues", "tickets", "tasks", "fix all", "one PR per", "implement these features", "work on #N", "tackle", "each in its own branch"

**Concept:** Each task gets its own isolated worktree and branch. Agents work independently on separate concerns. Each completed worktree can be merged individually, becoming its own commit (or PR if the user wants).

**Task decomposition:**
1. Gather the list of tasks — from GitHub issues, user description, or codebase analysis
2. For each task, define:
   - **name**: Short kebab-case identifier (e.g., `fix-auth-bug`, `add-dark-mode`, `issue-15`)
   - **prompt**: Self-contained description with full context. The agent knows nothing about the other tasks or this conversation.
3. Each prompt MUST include:
   - What to do (the task)
   - Where to find relevant code (files, modules, patterns)
   - What "done" looks like (acceptance criteria)
   - Instruction to write results to `{{RESULT_FILE}}`

**Spawn pattern:**
```
ppg spawn --name "fix-auth-bug" --prompt "Fix the authentication bug where..." --json --no-open
ppg spawn --name "add-dark-mode" --prompt "Implement dark mode toggle..." --json --no-open
ppg spawn --name "issue-15" --prompt "Resolve issue #15: ..." --json --no-open
```

Each command creates a separate worktree on its own `ppg/<name>` branch.

**Post-completion:**
1. Aggregate results: `ppg aggregate --all --json`
2. Present a summary table: task name, status, branch, key findings
3. Present a **merge checklist** — list each worktree with its status and ask which to merge
4. Merge confirmed ones: `ppg merge <wt-id> --json` (squash by default)
5. Optionally create PRs: `gh pr create --head ppg/<name> --title "..." --body "..."` (if user wants PRs instead of direct merges)

**Important:** In batch mode, always surface results and get user confirmation before merging. The user may want to review diffs, skip some tasks, or create PRs instead.

## GitHub Issue Integration

When the user references GitHub issues (e.g., `#12`, `#15`):

1. Fetch issue details: `gh issue view <number> --json title,body,labels,assignees`
2. Use the issue title and body as context for the agent prompt
3. Name the worktree after the issue: `issue-<number>`
4. After merge, optionally close the issue: `gh issue close <number>` (ask the user first)
