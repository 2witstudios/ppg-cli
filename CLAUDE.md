# ppg-cli — Claude Code Instructions

**Read `vision.md` first** — it's the source of truth for project goals, non-goals, constraints, and architecture decisions.

## Tech Stack

- **Language**: TypeScript (strict, ES2022, NodeNext module resolution), ESM-only
- **CLI framework**: Commander.js 14
- **Process execution**: execa 9
- **Testing**: Vitest 3 (colocated tests)
- **Build**: tsup (single ESM bundle with `#!/usr/bin/env node` banner)
- **File safety**: proper-lockfile 4 (manifest locking), write-file-atomic 7
- **IDs**: nanoid 5 (lowercase alphanumeric)
- **Config**: yaml 2

## Commands

```bash
npm run build      # tsup → dist/cli.js
npm run dev        # tsx src/cli.ts (unbundled, for development)
npm test           # vitest
npm run typecheck  # tsc --noEmit
```

## Source Architecture

```
src/
├── cli.ts              # Entry point — registers commands with Commander.js
├── commands/           # Command implementations (init, spawn, status, kill, attach, logs, aggregate, merge, list, clean, diff, restart, send, ui, wait, worktree)
├── core/               # Domain logic (manifest, agent, worktree, tmux, terminal, config, template, env, cleanup)
├── lib/                # Utilities (paths, errors, id, output, shell, cjs-compat)
└── types/              # Type definitions (manifest, config, common)
```

**Flow**: `cli.ts` → `commands/` → `core/` → `lib/` → `types/`

## Key Patterns

- **Lazy command imports** — `cli.ts` uses dynamic `import()` for each command to keep startup fast
- **Manifest locking** — Always use `updateManifest(projectRoot, updater)` for read-modify-write. Never read + write separately. Lock: 10s stale timeout, 5 retries
- **Atomic writes** — All manifest writes go through `write-file-atomic`
- **`PpgError` hierarchy** — Typed errors with codes: `TMUX_NOT_FOUND`, `NOT_GIT_REPO`, `NOT_INITIALIZED`, `MANIFEST_LOCK`, `WORKTREE_NOT_FOUND`, `AGENT_NOT_FOUND`, `MERGE_FAILED`, `INVALID_ARGS`, `AGENTS_RUNNING`, `WAIT_TIMEOUT`, `AGENTS_FAILED`, `NO_SESSION_ID`
- **Worktree resolution** — Use `resolveWorktree(manifest, ref)` from `core/manifest.ts` to look up worktrees by ID, name, or branch. Never duplicate the lookup pattern.
- **Dual output** — Every command supports `--json` flag. Use `output(data, json)` and `outputError(error, json)` from `lib/output.ts`
- **Functional style** — Pure functions, composition, `const`, destructuring, no classes except `PpgError`
- **Path helpers** — All path computation in `lib/paths.ts`: `ppgDir()`, `manifestPath()`, `resultFile()`, `worktreePath()`, etc.
- **Signal-stack status** — Agent status detection in `core/agent.ts:checkAgentStatus()`: result file → pane exists → pane dead → current command → running
- **ID generation** — `worktreeId()` → `wt-{6chars}`, `agentId()` → `ag-{8chars}` (lowercase alphanumeric via nanoid)
- **`.js` extensions in imports** — Required by NodeNext module resolution. All relative imports must include `.js` extension

## Testing

- **Framework**: Vitest 3
- **Location**: Colocated with source (e.g., `src/core/manifest.test.ts`)
- **Mocking**: Mock `execa` for tmux/git calls. Use `vi.mock` with `vi.importActual` for partial mocks
- **Start with**: Pure functions in `lib/` — they're easiest to test
- **Pattern**: `describe('unitName')` → `test('given X, should Y')`

## Domain Concepts

| Concept | Description |
|---------|-------------|
| **Worktree** | Isolated git checkout on branch `ppg/<name>`, lives in `.worktrees/wt-{id}/` |
| **Agent** | CLI process in a tmux pane, receives task via prompt file |
| **Manifest** | `.ppg/manifest.json` — runtime state: worktrees, agents, statuses, tmux targets |
| **Config** | `.ppg/config.yaml` — session name, agent definitions, directory paths |
| **Template** | Markdown in `.ppg/templates/` with `{{VAR}}` placeholders |
| **Result file** | `.ppg/results/{agentId}.md` — primary agent completion signal |

## Agent Lifecycle

```
spawning → running → completed  (result file written)
                   → failed     (non-zero exit or shell prompt visible)
                   → killed     (via ppg kill)
                   → lost       (tmux pane died unexpectedly)
```

**Spawn flow**: Generate IDs → `git worktree add` → setup env (copy .env, symlink node_modules) → create tmux window → split panes if count > 1 → write prompt file → `send-keys` agent command → update manifest → open Terminal.app window

**Merge flow**: Set worktree `merging` → `git merge --squash` (or `--no-ff`) → set `merged` → kill tmux window → teardown env → `git worktree remove` → delete branch → set `cleaned`

## Conductor Mode

A "conductor" is a meta-agent that drives ppg programmatically:

1. **Plan** — Break task into independent, parallelizable units
2. **Spawn** — `ppg spawn --name <name> --prompt <task> --json`
3. **Poll** — `ppg status --json` → check for `status: "completed"` or `status: "failed"`
4. **Aggregate** — `ppg aggregate --all --json` → collect result files
5. **Merge** — `ppg merge <worktree-id>` → squash merge back to base

Always use `--json` for machine-readable output. Poll status every 5s. One concern per worktree for clean merges.
