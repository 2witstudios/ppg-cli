# ppg — Vision

## Overview

ppg (Pure Point Guard) is a local orchestration runtime for parallel CLI coding agents. It spawns multiple AI agents in isolated git worktrees, each in its own tmux pane, and provides a single control plane to monitor, aggregate, and merge their work.

## Who It's For

- **Developers** using AI coding agents who want to parallelize tasks across a codebase
- **Meta-agent "conductors"** — AI agents that programmatically orchestrate other agents via `--json` output
- **Teams** scaling AI-assisted workflows beyond one-agent-at-a-time

## Goals

- **Parallel agent isolation** — Each agent works in its own git worktree on its own branch, with no file conflicts
- **Simple orchestration primitives** — `spawn`, `status`, `kill`, `aggregate`, `merge` — do one thing well
- **Agent-agnostic design** — Works with Claude Code, Codex, custom scripts, or any CLI agent
- **Manifest-based state** — Single `manifest.json` as the source of truth for all runtime state, with file-level locking and atomic writes
- **Human + conductor workflows** — Pretty tables for humans, `--json` for machine consumption
- **Template system** — Reusable prompt templates with `{{VAR}}` substitution

## Non-Goals

- Not a cloud service — ppg runs locally on your machine
- Not an IDE or editor — ppg is a CLI tool
- Not agent logic — ppg spawns and monitors agents, it doesn't implement agent behavior
- Not CI/CD — ppg is for interactive development, not automated pipelines
- Not cross-platform yet — macOS-first (Terminal.app auto-open via AppleScript)

## Key Constraints

- **macOS-first** — Terminal.app auto-open uses AppleScript via `osascript`; tmux features work anywhere
- **Requires tmux + git worktrees** — these are the foundational abstractions
- **Node.js >= 20** — ESM-only, modern TypeScript
- **Single-repo** — all worktrees are branches of the same repository
- **Local filesystem** — manifest, config, prompts, results, and templates all live in `.pg/`

## Architecture Decisions

- **Worktree isolation model** — Git worktrees provide true filesystem isolation with shared history. Branch naming: `ppg/<name>`. Path: `.worktrees/wt-{id}/`
- **tmux process management** — One session per project, one window per worktree, one pane per agent. tmux provides attach, logs, kill, and status detection for free
- **Manifest with file-level locking** — `proper-lockfile` (10s stale, 5 retries) + `write-file-atomic` for safe concurrent access from multiple ppg commands
- **Template `{{VAR}}` system** — Simple, no dependencies, built-in variables for agent context (WORKTREE_PATH, BRANCH, AGENT_ID, RESULT_FILE, etc.)
- **Agent-agnostic config** — Agents defined in `.pg/config.yaml` with `command`, `promptFlag`, `interactive` properties. Default: Claude Code
- **Signal-stack status detection** — Layered priority: result file → pane existence → pane liveness → current command → running. No IPC required

## Success Criteria

- `ppg init` to 3+ parallel agents running in < 2 minutes
- Conductor meta-agent can plan, spawn, poll, aggregate, and merge via `--json` without human intervention
- Status detection accurately reflects agent state through the full lifecycle (spawning → running → completed/failed/killed/lost)
- No data loss from concurrent manifest access
- Clean worktree lifecycle: create → work → merge → cleanup with no orphaned branches or directories
