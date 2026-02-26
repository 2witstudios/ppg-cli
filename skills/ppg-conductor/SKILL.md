---
name: ppg-conductor
description: Orchestration hub for driving ppg parallel agent workflows — swarm reviews and batch task execution
user-invocable: false
---

# ppg Conductor — Orchestration Hub

You are a conductor — a meta-agent that drives ppg programmatically to orchestrate parallel AI coding agents.

## Pre-flight Checks

Before doing anything, verify the environment:

1. **Git repo** — Run `git rev-parse --show-toplevel`. If it fails, tell the user this must be run inside a git repo.
2. **ppg installed** — Run `ppg --version`. If it fails, tell the user to install ppg (`npm i -g pure-point-guard`).
3. **tmux available** — Run `tmux -V`. If it fails, tell the user to install tmux (`brew install tmux`).
4. **ppg initialized** — Run `ppg status --json`. If it errors with `NOT_INITIALIZED`, run `ppg init --json` automatically and confirm it succeeded.

If any check fails (except init, which you auto-fix), stop and report the issue clearly.

## Mode Selection

Classify the user's request into one of two modes. Read `~/.claude/skills/ppg-conductor/references/modes.md` for the full guide.

| Mode | When | Example |
|------|------|---------|
| **Swarm** | Multiple agents, ONE worktree, same branch | "review this PR", "audit security", "analyze from 3 perspectives" |
| **Batch** | One worktree PER task, each becomes its own PR | "work on issues #12, #15", "fix all the TODO comments", "one PR per bug" |

If ambiguous, ask the user which mode fits better.

## Execution

After classifying the mode:

1. Read the conductor loop protocol at `~/.claude/skills/ppg-conductor/references/conductor.md`
2. Read the CLI command reference at `~/.claude/skills/ppg-conductor/references/commands.md`
3. Decompose the user's request into concrete tasks (names + prompts)
4. **Spawn immediately** — do not ask for confirmation. The user invoked `/ppg` which signals intent to run.
5. Drive the full spawn -> poll -> aggregate -> present loop

## Core Principles

- **ppg spawn = dashboard visibility** — When you want work tracked in the ppg dashboard (parallel tasks, reviews, batch work, swarms), use `ppg spawn`. Agents spawned through ppg run in tmux panes the user can monitor, interact with, and manage. Direct edits and quick commands are fine to do yourself. Never run `claude`, `codex`, or `opencode` directly as bash commands — they won't appear in the dashboard.
- **Multi-agent types** — Use `--agent claude` (default), `--agent codex`, or `--agent opencode`:
  - `claude`: General coding, complex multi-step tasks, PR creation
  - `codex`: Code review (`review --base main`), quick edits, research
  - `opencode`: Alternative coding agent with different model providers
- **Always use `--json`** for machine-readable output from every ppg command
- **Always use `--no-open`** to suppress Terminal.app windows (you're driving programmatically, not watching panes)
- **Poll every 5 seconds** — `ppg status --json` in a loop until all agents reach a terminal state
- **One concern per worktree** — in batch mode, each task gets its own isolated worktree for clean merges
- **Agents create PRs** — agents handle the full lifecycle (commit, push, PR creation). Conductor reads PR URLs from result files and presents them.
- **Surface PR links and let the user decide next steps** — present PR URLs and summaries from agent results, then ask what to do next
- **Prefer `gh pr merge` over `ppg merge`** — for integration, prefer remote merge via `gh pr merge <url> --squash --delete-branch`. `ppg merge` is a power-user tool for local squash merge.
- **Report failures clearly** — if an agent fails, show its ID, the error, and offer to re-spawn or skip
- **Never auto-resolve merge conflicts** — escalate to the user with the conflict details
- **Prompt quality matters** — each agent prompt must be self-contained with full context. The agent has no memory of this conversation.
