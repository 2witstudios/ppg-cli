# ppg — Vision

## Overview

ppg (Pure Point Guard) is a local orchestration system for parallel AI coding agents, driven through a native macOS dashboard. The dashboard is the primary interface — it lets you spawn, monitor, and merge agents visually. Underneath, a CLI engine manages git worktrees, tmux sessions, status tracking, and branch merging.

## Who It's For

- **Developers** using AI coding agents who want to parallelize tasks across a codebase
- **Meta-agent "conductors"** — AI agents that programmatically orchestrate other agents via `--json` output
- **Teams** scaling AI-assisted workflows beyond one-agent-at-a-time

## Goals

- **Visual dashboard as primary interface** — A native macOS app that reads the manifest in real time, providing spawn controls, live status, log streaming, diffs, and merge actions in a single window
- **Parallel agent isolation** — Each agent works in its own git worktree on its own branch, with no file conflicts
- **Simple orchestration primitives** — `spawn`, `status`, `kill`, `aggregate`, `merge` — do one thing well
- **Agent-agnostic design** — Works with Claude Code, Codex, custom scripts, or any CLI agent
- **Manifest-based state** — Single `manifest.json` as the source of truth for all runtime state, with file-level locking and atomic writes
- **Human + conductor workflows** — Dashboard for visual use, pretty tables for the terminal, `--json` for machine consumption
- **Template system** — Reusable prompt templates with `{{VAR}}` substitution

## Non-Goals

- Not a cloud service — ppg runs locally on your machine
- Not an IDE or editor — ppg is for agent orchestration, not code editing
- Not agent logic — ppg spawns and monitors agents, it doesn't implement agent behavior
- Not CI/CD — ppg is for interactive development, not automated pipelines
- Not cross-platform yet — macOS-first (Terminal.app auto-open via AppleScript)

## Key Constraints

- **macOS-first** — Terminal.app auto-open uses AppleScript via `osascript`; tmux features work anywhere
- **Requires tmux + git worktrees** — these are the foundational abstractions
- **Node.js >= 20** — ESM-only, modern TypeScript
- **Single-repo** — all worktrees are branches of the same repository
- **Local filesystem** — manifest, config, prompts, results, and templates all live in `.ppg/`

## Architecture Decisions

- **Native macOS dashboard** — A Swift app that watches the manifest file and provides the primary user interface. The dashboard reads the same `manifest.json` the CLI writes, keeping the two fully decoupled — no IPC, no server
- **Worktree isolation model** — Git worktrees provide true filesystem isolation with shared history. Branch naming: `ppg/<name>`. Path: `.worktrees/wt-{id}/`
- **tmux process management** — One session per project, one window per worktree, one pane per agent. tmux provides attach, logs, kill, and status detection for free
- **Manifest with file-level locking** — `proper-lockfile` (10s stale, 5 retries) + `write-file-atomic` for safe concurrent access from multiple ppg commands
- **Template `{{VAR}}` system** — Simple, no dependencies, built-in variables for agent context (WORKTREE_PATH, BRANCH, AGENT_ID, RESULT_FILE, etc.)
- **Agent-agnostic config** — Agents defined in `.ppg/config.yaml` with `command`, `promptFlag`, `interactive` properties. Default: Claude Code
- **Signal-stack status detection** — Layered priority: result file → pane existence → pane liveness → current command → running. No IPC required

## Success Criteria

- `ppg init` to 3+ parallel agents running in < 2 minutes
- Conductor meta-agent can plan, spawn, poll, aggregate, and merge via `--json` without human intervention
- Status detection accurately reflects agent state through the full lifecycle (spawning → running → completed/failed/killed/lost)
- No data loss from concurrent manifest access
- Clean worktree lifecycle: create → work → merge → cleanup with no orphaned branches or directories
