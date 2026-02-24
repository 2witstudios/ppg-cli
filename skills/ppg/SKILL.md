---
name: ppg
description: Orchestrate parallel AI coding agents with ppg — review PRs with swarms, tackle GH issues in batch, or run any parallelizable task
user-invocable: true
---

# /ppg — Parallel Agent Conductor

Read and follow the conductor hub instructions in `~/.claude/skills/ppg-conductor/SKILL.md`.
Read the mode guide at `~/.claude/skills/ppg-conductor/references/modes.md`.
Read the conductor loop protocol at `~/.claude/skills/ppg-conductor/references/conductor.md`.
Read the CLI command reference at `~/.claude/skills/ppg-conductor/references/commands.md`.

Run pre-flight checks. Classify the user's request as swarm or batch mode. Decompose into concrete tasks with descriptive names and self-contained prompts. Spawn immediately — do not ask for confirmation. Drive the full conductor loop: spawn, poll, aggregate, (merge if batch), summarize.

If the user provides no arguments (just `/ppg`), ask what they'd like to parallelize.
