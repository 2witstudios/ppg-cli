---
name: pogu
description: Orchestrate parallel AI coding agents with pogu — review PRs with swarms, tackle GH issues in batch, or run any parallelizable task
user-invocable: true
---

# /pogu — Parallel Agent Conductor

Read and follow the conductor hub instructions in `~/.claude/skills/pogu-conductor/SKILL.md`.

Run pre-flight checks. Classify the user's request as swarm or batch mode. Decompose into concrete tasks with descriptive names and self-contained prompts. Spawn immediately — do not ask for confirmation. Drive the full conductor loop: spawn, poll, aggregate, (agents create PRs), summarize.

If the user provides no arguments (just `/pogu`), ask what they'd like to parallelize.
