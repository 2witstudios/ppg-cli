# Performance Research Findings

---

## Agent 1: CLI Startup & Command Execution Bottlenecks

*Agent ID: `ag-gwr0a74p`*

# Result: ag-gwr0a74p

## Summary
Performed a comprehensive performance profile of the ppg-cli startup path, command execution hot paths, import graph, and build output. Identified specific bottlenecks and optimization opportunities ranked by impact.

## Startup Time Analysis

### Entry Point: `src/cli.ts`

The entry point is well-designed with two **eagerly loaded** imports and all command handlers **lazily loaded** via dynamic `import()`:

**Eager imports (loaded on every invocation):**
1. `commander` — CLI framework (~50KB), unavoidable
2. `./lib/errors.js` — `PgError` class, tiny (~70 lines), zero deps
3. `./lib/output.js` — `outputError` function, tiny, depends only on `../types/manifest.js` (type-only)

**Lazy imports (loaded per-command via `await import()`):**
- All 10 commands: `init`, `spawn`, `status`, `kill`, `attach`, `logs`, `aggregate`, `merge`, `list`, `ui`

**Verdict:** Startup path is clean. Only `commander`, `errors`, and `output` load eagerly. This is correct and minimal.

### Bundle Analysis: tsup Output

The bundle at `dist/cli.js` is **60KB / 2062 lines** — very reasonable for a CLI tool.

tsup config (`tsup.config.ts`):
- `splitting: false` — **All code goes into one file**, no code-splitting for lazy commands
- `noExternal: []` — External deps (`commander`, `execa`, `yaml`, `nanoid`, `proper-lockfile`, `write-file-atomic`) are **NOT bundled**; they come from `node_modules`

**Critical finding:** tsup uses `__esm()` wrappers to emulate lazy loading (24 lazy modules in the bundle). The dynamic `import()` calls in `cli.ts` **do NOT actually code-split** because `splitting: false`. However, the `__esm()` pattern provides **module-level lazy initialization** — code in each `__esm()` block only executes when first referenced. So the lazy import pattern in source is partially preserved in the bundle, but the module evaluation still triggers all top-level imports in the dependency chain.

**External dependency load order per command:**

| Dependency | Size/Weight | Loaded By | When |
|---|---|---|---|
| `commander` | Medium | cli.ts | Always (eager) |
| `execa` | Heavy (~complex, many deps) | worktree.ts, tmux.ts, init.ts, terminal.ts, merge.ts, ui.ts | Any command except `list templates` |
| `yaml` | Medium | config.ts | `spawn`, `init`, `list` |
| `nanoid` | Tiny | id.ts | `spawn` only |
| `proper-lockfile` | Medium | cjs-compat.ts (lazy) | `status`, `spawn`, `kill`, `merge`, `aggregate` (any `updateManifest` call) |
| `write-file-atomic` | Small | cjs-compat.ts (lazy) | Same as proper-lockfile |

### Import Chain Depths (Most Common Commands)

**`ppg status`:**
```
cli.ts → commands/status.ts
  → core/config.ts → yaml, fs, lib/paths
  → core/manifest.ts → fs, lib/paths, lib/cjs-compat → (lazy: proper-lockfile, write-file-atomic)
  → core/agent.ts → fs, lib/paths, core/tmux → execa
  → core/worktree.ts → execa, lib/paths
  → lib/errors.ts
  → lib/output.ts
```
Depth: 3 levels. Loads: `execa`, lazy `proper-lockfile` + `write-file-atomic`. Does NOT load `yaml` (no config needed).

**`ppg spawn`:**
```
cli.ts → commands/spawn.ts
  → core/config.ts → yaml, fs
  → core/manifest.ts → (everything above)
  → core/worktree.ts → execa
  → core/env.ts → fs, path
  → core/template.ts → fs, path
  → core/agent.ts → fs, core/tmux → execa
  → core/tmux.ts → execa
  → core/terminal.ts → execa
  → lib/id.ts → nanoid
  → lib/paths.ts → path
  → lib/errors.ts
  → lib/output.ts
```
Depth: 3 levels. Loads: ALL external deps. This is the heaviest command.

**`ppg kill`:**
```
cli.ts → commands/kill.ts
  → core/manifest.ts → (lazy: proper-lockfile, write-file-atomic)
  → core/agent.ts → core/tmux → execa
  → core/worktree.ts → execa
  → core/env.ts → fs
  → core/tmux.ts → execa
  → lib/errors.ts
  → lib/output.ts
```
Depth: 3 levels. Loads: `execa`, lazy `proper-lockfile` + `write-file-atomic`. Does NOT load `yaml` or `nanoid`.

## Command-by-Command Hot Path Analysis

### `ppg status` — Read-heavy, Sequential Agent Checks

**Hot path** (`src/commands/status.ts:15-26`):
1. `getRepoRoot()` → spawns `git rev-parse --show-toplevel` subprocess (`src/core/worktree.ts:5-13`)
2. `updateManifest()` with `refreshAllAgentStatuses()`:
   - Acquires file lock (proper-lockfile) (`src/core/manifest.ts:36-51`)
   - Reads manifest JSON from disk (`src/core/manifest.ts:19-23`)
   - **For EACH agent** in EACH worktree, **sequentially** calls `checkAgentStatus()` (`src/core/agent.ts:135-166`)
     - `fs.access()` on result file (`src/core/agent.ts:99`)
     - `tmux display-message` subprocess for pane info (`src/core/agent.ts:105`, `src/core/tmux.ts:120-138`)
     - Potentially another `fs.access()` on result file (`src/core/agent.ts:114` or `124`)
   - Writes manifest back with `write-file-atomic`
   - Releases lock

**Bottleneck:** `refreshAllAgentStatuses()` at `src/core/agent.ts:135-166` — **sequential nested loop** over all worktrees/agents. Each agent check spawns 1-3 subprocesses (`fs.access` + `tmux display-message`). With 10 agents across 3 worktrees, this is **10-30 sequential subprocess calls**.

**In watch mode** (`src/commands/status.ts:55-73`): This entire cycle repeats every 2 seconds, including lock acquisition.

### `ppg spawn` — Most Complex, Many Sequential Steps

**Hot path** (`src/commands/spawn.ts:93-212`):
1. `getRepoRoot()` → git subprocess
2. `loadConfig()` → reads YAML file, parses with `yaml` library (`src/core/config.ts:40-52`)
3. `readManifest()` → reads JSON file
4. `getCurrentBranch()` → git subprocess (`src/core/worktree.ts:16-21`)
5. `createWorktree()` → git subprocess (`src/core/worktree.ts:28-40`)
6. `setupWorktreeEnv()` → **sequential** fs.access + fs.copyFile for each .env file, then symlink (`src/core/env.ts:5-39`)
7. `readManifest()` again → **redundant re-read** (`src/commands/spawn.ts:117`)
8. `tmux.ensureSession()` → tmux subprocess (has-session, maybe new-session) (`src/core/tmux.ts:21-24`)
9. `tmux.createWindow()` → tmux subprocess (`src/core/tmux.ts:26-40`)
10. **For each agent (sequential):**
    - If i>0: `tmux.splitPane()` → tmux subprocess
    - `renderTemplate()` → pure string replacement (fast)
    - `spawnAgent()`:
      - `fs.writeFile()` prompt file (`src/core/agent.ts:50`)
      - `tmux.sendKeys()` → **2 tmux subprocesses** (send-keys literal + send-keys Enter) (`src/core/tmux.ts:59-63`)
11. `updateManifest()` → lock + read + write + unlock
12. `openTerminalWindow()` → osascript subprocess (`src/core/terminal.ts:7-27`)

**Bottleneck:** Steps 1-4 are all sequential git/fs calls that could partially overlap. Steps 6-7 have a redundant manifest read. The agent spawn loop (step 10) is sequential — `tmux.sendKeys` makes 2 subprocess calls per agent.

### `ppg kill` — Sequential Agent Kill with 2s Sleep

**Hot path** (`src/commands/kill.ts:64-110`):
1. `getRepoRoot()` → git subprocess
2. `readManifest()` → file read
3. **For each agent**: `killAgent()` at `src/core/agent.ts:168-181`:
   - `tmux.sendCtrlC()` → tmux subprocess
   - **`await new Promise(resolve => setTimeout(resolve, 2000))`** ← **2-second hard sleep per agent**
   - `getPaneInfo()` → tmux subprocess
   - Optionally `tmux.killPane()` → tmux subprocess
4. `updateManifest()` → lock + read + write + unlock

**Bottleneck:** The **2-second sleep in `killAgent()`** at `src/core/agent.ts:174` is the dominant cost. Killing 5 agents takes **~10 seconds minimum** due to sequential sleeps.

### `ppg merge` — Multiple Sequential Manifest Updates

**Hot path** (`src/commands/merge.ts:18-143`):
1. Refreshes all agent statuses (same bottleneck as `status`)
2. `updateManifest()` to set status to 'merging' (`line 56-61`)
3. `execa('git', ['merge', ...])` → git subprocess
4. Optionally `execa('git', ['commit', ...])` → git subprocess
5. `updateManifest()` to set status to 'merged' (`line 79-85`)
6. Cleanup: `tmux.killWindow()`, `teardownWorktreeEnv()`, `removeWorktree()` — 3+ subprocess calls
7. `updateManifest()` to set status to 'cleaned' (`line 123-128`)

**Bottleneck:** **3 separate `updateManifest()` calls** in the success path, each acquiring a file lock, reading, writing, and releasing. These could be consolidated.

## Specific Bottlenecks Identified

### P0 — High Impact

1. **Sequential agent status checks** — `src/core/agent.ts:135-166`
   - `refreshAllAgentStatuses()` checks agents one-by-one with subprocess calls
   - **Fix:** Use `Promise.all()` to check all agents in parallel
   - **Impact:** O(n) → O(1) for n agents. With 10 agents, ~10x faster status checks.

2. **2-second sleep in killAgent** — `src/core/agent.ts:174`
   - Hard `setTimeout(2000)` per agent, sequentially
   - **Fix:** Kill all agents concurrently with `Promise.all()`, or use a single sleep after sending all Ctrl-C signals
   - **Impact:** n*2s → 2s for n agents

3. **Sequential tmux.sendKeys (2 subprocesses)** — `src/core/tmux.ts:59-63`
   - Two separate `execa` calls: one for literal text, one for Enter
   - **Fix:** Combine into single tmux command or use `send-keys` without `-l` and append Enter directly
   - **Impact:** 2 subprocess calls → 1 per agent spawn

### P1 — Medium Impact

4. **Redundant manifest read in spawn** — `src/commands/spawn.ts:117`
   - After `readManifest()` at line 37 for initialization check, reads again at line 117 just to get `sessionName`
   - **Fix:** Reuse manifest from the initial read (or at least cache `sessionName`)
   - **Impact:** Eliminates 1 file read

5. **Multiple updateManifest calls in merge** — `src/commands/merge.ts:56,79,123`
   - 3 lock-acquire-read-write-release cycles in one command
   - **Fix:** Batch status transitions where possible (merging → merged → cleaned could be 1-2 calls)
   - **Impact:** Eliminates 1-2 lock cycles

6. **`getRepoRoot()` called on every command** — `src/core/worktree.ts:5-13`
   - Spawns `git rev-parse` subprocess every time, even though it rarely changes
   - **Fix:** Cache result for the process lifetime (it's the same process, same cwd)
   - **Impact:** Eliminates 1 subprocess call per command

7. **Sequential env file setup** — `src/core/env.ts:10-19`
   - `fs.access` + `fs.copyFile` sequentially for each `.env` file
   - **Fix:** `Promise.all()` for all env files
   - **Impact:** Minor, but contributes to spawn latency

### P2 — Low Impact / Quick Wins

8. **`proper-lockfile` and `write-file-atomic` lazy loading in cjs-compat.ts** — `src/lib/cjs-compat.ts:9-23`
   - Currently caches after first load — this is correct and good
   - No change needed; already well-implemented

9. **`yaml` library loaded unnecessarily for status** — currently NOT loaded for status (only config.ts is imported by spawn/init/list)
   - Verified: `status.ts` does not import `config.ts`. Good.

10. **`nanoid` loaded at module level** — `src/lib/id.ts:1-6`
    - `customAlphabet` is called at module init time, creating the RNG functions
    - Only needed by `spawn`. Since `spawn.ts` is lazy-loaded, this is fine.
    - No change needed.

11. **`isInsideTmux()` is async but just checks env var** — `src/core/tmux.ts:154-156`
    - Returns `!!process.env.TMUX` — no reason to be async
    - **Fix:** Make synchronous
    - **Impact:** Negligible but cleaner API

## Optimization Suggestions (Ranked by Impact)

### Quick Wins (< 30 min each)

| # | Change | File | Impact |
|---|---|---|---|
| 1 | **Parallelize `refreshAllAgentStatuses()`** — use `Promise.all()` for agent checks | `src/core/agent.ts:135-166` | 5-10x faster status for multi-agent setups |
| 2 | **Parallelize `killAgent()` calls** — send all Ctrl-C first, one sleep, then check all | `src/commands/kill.ts:77-83` + `src/core/agent.ts:168-181` | n*2s → ~2s |
| 3 | **Cache `getRepoRoot()` result** — memoize for process lifetime | `src/core/worktree.ts:5-13` | Save 1 subprocess/command |
| 4 | **Remove redundant `readManifest` in spawn** | `src/commands/spawn.ts:117` | Save 1 file read |
| 5 | **Combine `tmux.sendKeys` into single call** | `src/core/tmux.ts:59-63` | Save 1 subprocess/agent |

### Larger Refactors (1-4 hours)

| # | Change | Files | Impact |
|---|---|---|---|
| 6 | **Batch manifest updates in merge** — reduce from 3 to 1-2 lock cycles | `src/commands/merge.ts` | Reduces lock contention and I/O |
| 7 | **Parallelize env setup** — `Promise.all` for .env copies + symlink | `src/core/env.ts` | Minor but contributes to spawn speed |
| 8 | **Enable tsup `splitting: true`** — true code splitting for lazy commands | `tsup.config.ts` | Real deferred loading (currently all code evaluates on first import chain) |

### Not Worth Changing

- `commander` eager import — unavoidable, it's the CLI framework
- `execa` eager per-command — needed by virtually all commands; only avoidable for `list templates`
- `lib/errors.ts` and `lib/output.ts` eager — tiny, zero-dep modules
- `cjs-compat.ts` lazy caching — already correctly implemented

## Build Output Assessment

- **Bundle size: 60KB** — excellent for a CLI tool
- **No tree-shaking concerns** — the code is lean, no dead exports visible
- **`splitting: false`** means all 24 modules are in one file. Enabling `splitting: true` would create separate chunks per lazy-imported command, giving true deferred loading. However, since Node.js module loading is fast for small bundles, the 60KB single-file approach is acceptable and simpler for distribution.
- **External deps not bundled** — correct choice; avoids bloating the bundle with `execa` (which has many transitive deps) and allows npm dedup

## Changes
No files changed — this was a read-only analysis.

## Notes
- The codebase is well-structured with a clean separation of concerns
- The lazy import pattern in `cli.ts` is correctly implemented
- The `cjs-compat.ts` lazy loading for CJS packages is well done
- The biggest wins are from **parallelizing sequential subprocess calls** — particularly `refreshAllAgentStatuses()` and `killAgent()` loops
- The 2-second hardcoded sleep in `killAgent` is the single most impactful bottleneck for the `kill` command
- For conductor mode (polling `ppg status --json` every 5s), the sequential agent status check is the most critical path to optimize



---

## Agent 2: Git Worktree & Tmux Operations

*Agent ID: `ag-ytucy0l7`*

# Result: ag-ytucy0l7

## Summary
Analyzed ppg-cli's git worktree, tmux, and environment management layers for performance optimization opportunities. Traced every external command invocation across the spawn, status, merge, and kill workflows.

## Changes
No files changed — this is a research/analysis task.

## Notes

---

# Performance Analysis: Git Worktree & Tmux Operations

## 1. Spawn Workflow — Operation Inventory

### New worktree spawn (`spawnNewWorktree`)

**Sequential external commands executed** (for a single agent):

| # | Command | Source | Blocking? |
|---|---------|--------|-----------|
| 1 | `git rev-parse --show-toplevel` | `getRepoRoot()` | Yes |
| 2 | `git branch --show-current` | `getCurrentBranch()` (if no `--base`) | Yes |
| 3 | `git worktree add <path> -b <branch> [base]` | `createWorktree()` | Yes |
| 4 | `fs.access` + `fs.copyFile` per env file | `setupWorktreeEnv()` | Yes |
| 5 | `fs.access` + `fs.lstat` + `fs.symlink` (node_modules) | `setupWorktreeEnv()` | Yes |
| 6 | `fs.readFile` (manifest) | `readManifest()` | Yes |
| 7 | `tmux has-session -t <name>` | `sessionExists()` via `ensureSession()` | Yes |
| 8 | `tmux new-session` (conditional) | `ensureSession()` | Conditional |
| 9 | `tmux new-window -t <session> -n <name> -c <cwd>` | `createWindow()` | Yes |
| 10 | `fs.writeFile` (prompt file) | `spawnAgent()` | Yes |
| 11 | `tmux send-keys -t <target> -l <command>` | `sendKeys()` | Yes |
| 12 | `tmux send-keys -t <target> Enter` | `sendKeys()` | Yes |
| 13 | `lockfile.lock` + `fs.readFile` + `writeFileAtomic` + `lockfile.unlock` | `updateManifest()` | Yes |
| 14 | `osascript` (Terminal.app) | `openTerminalWindow()` | Yes |

**Total: 12-14 external process invocations** for a single-agent spawn.

For `count > 1` agents, each additional agent adds:
- `tmux split-window` (1 command)
- `fs.writeFile` (prompt file)
- `tmux send-keys` × 2

### Identified Issues

#### Issue 1: `sendKeys` uses two separate tmux commands
**File**: `src/core/tmux.ts:59-63`
```typescript
await execa('tmux', ['send-keys', '-t', target, '-l', command]);
await execa('tmux', ['send-keys', '-t', target, 'Enter']);
```
**Impact**: Every agent spawn makes 2 process invocations where 1 would suffice.
**Fix**: Combine into a single call — `tmux send-keys -t <target> '<command>' Enter`. The `-l` flag (literal) is only needed for the command text; appending `Enter` as a separate key in the same call works: `tmux send-keys -t <target> -l '<command>' -- Enter`. Alternatively, just append a newline to the command text with `-l`.

**Estimated savings**: 1 `execa` call per agent spawn (~5-15ms each).

#### Issue 2: Manifest read before `ensureSession` is unnecessary duplication
**File**: `src/commands/spawn.ts:117`
```typescript
const manifest = await readManifest(projectRoot);
await tmux.ensureSession(manifest.sessionName);
```
The manifest was already verified readable at line 37. This second read is solely to get `sessionName`. But `loadConfig` at line 33 also loads the config which has the session name. If the session name were part of config (or cached), this read could be eliminated.

**Impact**: 1 redundant `fs.readFile` + JSON parse per spawn.

#### Issue 3: `ensureSession` always checks `has-session` before potentially creating
**File**: `src/core/tmux.ts:21-24`
This is correct for correctness but costs 1 process invocation per spawn even when the session invariably exists (common case after the first spawn).

**Optimization**: Could use `tmux new-session -d -s <name> 2>/dev/null || true` pattern — attempt creation, silently fail if exists. Reduces from 2 calls (check + create) to 1 call. Or cache session existence in the manifest/memory.

#### Issue 4: Sequential env file copying
**File**: `src/core/env.ts:10-19`
Each env file is copied sequentially with an `fs.access` check first.
**Fix**: Use `Promise.all` to parallelize all `copyFile` operations. The `access` check is redundant — just try `copyFile` and catch `ENOENT`.

#### Issue 5: Env setup and tmux setup are sequential but independent
**File**: `src/commands/spawn.ts:114-121`
```typescript
await setupWorktreeEnv(projectRoot, wtPath, config);   // file I/O only
const manifest = await readManifest(projectRoot);
await tmux.ensureSession(manifest.sessionName);         // tmux only
const windowTarget = await tmux.createWindow(...);      // tmux only
```
`setupWorktreeEnv` (file copies + symlinks) and `ensureSession` + `createWindow` (tmux operations) have no data dependency. They could run in parallel.

**Estimated savings**: ~20-50ms (overlapping I/O with tmux session setup).

#### Issue 6: `openTerminalWindow` is awaited but its result is unused
**File**: `src/commands/spawn.ts:187-188`
The `osascript` call to open Terminal.app takes 100-500ms. It already has try/catch with a warning. This could be fire-and-forget since the spawn is already complete.

**Estimated savings**: 100-500ms per spawn.

---

## 2. Status Workflow — Operation Inventory

### `statusCommand` / `refreshAllAgentStatuses`

Per status check, for N agents across M worktrees:

| Per agent | Command | Source |
|-----------|---------|--------|
| 1 | `fs.access(resultFile)` | `fileExists()` — check #1 |
| 2 | `tmux display-message -t <target> -p <format>` | `getPaneInfo()` |
| 3 | `fs.access(resultFile)` (conditional, if pane dead) | `fileExists()` — check #2 |
| 4 | `fs.access(resultFile)` (conditional, if shell visible) | `fileExists()` — check #3 |

Plus per worktree:
| 1 | `fs.access(wt.path)` | directory existence check |

**Total**: Up to 3 × `fs.access` + 1 × `tmux display-message` **per agent, per poll cycle**.

### Identified Issues

#### Issue 7: Sequential agent status checks — no parallelization
**File**: `src/core/agent.ts:139-149`
```typescript
for (const wt of Object.values(manifest.worktrees)) {
  for (const agent of Object.values(wt.agents)) {
    const { status, exitCode } = await checkAgentStatus(agent, projectRoot);
```
Every agent is checked sequentially. With 10 agents, this means 10 sequential `tmux display-message` invocations. Each `execa` call takes ~5-15ms.

**Fix**: Use `Promise.all` (or `Promise.allSettled`) to check all agents in parallel:
```typescript
const checks = agents.map(agent => checkAgentStatus(agent, projectRoot));
const results = await Promise.all(checks);
```

**Estimated savings**: With 10 agents × ~10ms each: from ~100ms to ~15ms (bounded by slowest single check).

#### Issue 8: Redundant `fileExists` calls in `checkAgentStatus`
**File**: `src/core/agent.ts:99-128`
The function checks `fileExists(agent.resultFile)` up to 3 times:
1. Line 99: Initial check
2. Line 114: Re-check if pane is dead
3. Line 125: Re-check if shell is visible

In the common "running" case, only check #1 + the tmux query happen. But in the "pane dead" and "shell visible" paths, there's a redundant re-check. This is minor since `fs.access` is very fast (~0.1ms), but it's slightly wasteful.

#### Issue 9: `status --watch` refreshes every 2 seconds with full manifest lock
**File**: `src/commands/status.ts:55-80`
The watch loop calls `updateManifest` with `refreshAllAgentStatuses` every 2 seconds. This acquires a file lock, reads, does all the status checks, writes, and releases. If another command (like `spawn`) runs during a status poll, it must wait for the lock.

**Optimization**: Consider a read-only status check that doesn't need to write to the manifest, with periodic write-back (e.g., every 5th poll or only when status changes). This reduces lock contention.

#### Issue 10: Batch tmux queries with `list-panes`
**File**: `src/core/tmux.ts:98-118` vs `120-139`
There are two functions: `listPanes(target)` (gets all panes in a window) and `getPaneInfo(target)` (gets info for one pane). Status checking uses `getPaneInfo` per agent — one `tmux display-message` per agent.

**Optimization**: For worktrees with multiple agents in the same window, use a single `tmux list-panes -t <window>` call to get all pane info at once, then match by pane ID. This reduces N tmux calls per window to 1.

**Estimated savings**: For a worktree with 4 agents: 4 tmux calls → 1 tmux call.

---

## 3. Merge Workflow — Operation Inventory

For a full merge with cleanup:

| # | Command | Source |
|---|---------|--------|
| 1 | `git rev-parse --show-toplevel` | `getRepoRoot()` |
| 2 | `lockfile.lock` + manifest read + status refresh (N agent checks) + write + unlock | `updateManifest(refreshAllAgentStatuses)` |
| 3 | `lockfile.lock` + manifest read + set `merging` + write + unlock | `updateManifest()` |
| 4 | `git merge --squash <branch>` | merge |
| 5 | `git commit -m <message>` | commit |
| 6 | `lockfile.lock` + manifest read + set `merged` + write + unlock | `updateManifest()` |
| 7 | `tmux kill-window -t <target>` | cleanup |
| 8 | `fs.lstat` + `fs.unlink` (node_modules symlink) | `teardownWorktreeEnv()` |
| 9 | `git worktree remove <path> --force` | `removeWorktree()` |
| 10 | `git branch -D <branch>` | `removeWorktree()` |
| 11 | `lockfile.lock` + manifest read + set `cleaned` + write + unlock | `updateManifest()` |

**Total: 11+ external commands + 4 manifest lock/read/write cycles**.

### Identified Issues

#### Issue 11: Four separate manifest update cycles in a single merge
**File**: `src/commands/merge.ts`
The merge command acquires the manifest lock 4 times:
1. Line 23: Refresh statuses
2. Line 56: Set `merging`
3. Line 79: Set `merged`
4. Line 123: Set `cleaned`

Each cycle: lock → read → parse → update → serialize → write → unlock. That's 4 lock acquisitions, 4 file reads, 4 file writes.

**Fix**: Combine status transitions. For example, after the merge git operations succeed, do a single update `merging → merged`. After cleanup, do a single update `merged → cleaned`. This cuts 4 lock cycles to 2-3.

**Estimated savings**: ~20-40ms (file I/O + lock overhead per cycle).

#### Issue 12: Cleanup operations are sequential but partially independent
**File**: `src/commands/merge.ts:99-128`
`killWindow`, `teardownWorktreeEnv`, and the start of `removeWorktree` are sequential. The tmux kill and env teardown could run in parallel since they affect different resources.

However, `teardownWorktreeEnv` (removing node_modules symlink) must happen before `git worktree remove` — this dependency is correct.

**Fix**: Run `killWindow` and `teardownWorktreeEnv` in parallel, then `removeWorktree` after.

#### Issue 13: `squash` merge uses 2 git commands where 1 might suffice
**File**: `src/commands/merge.ts:69-72`
```typescript
await execa('git', ['merge', '--squash', wt.branch], { cwd: projectRoot });
await execa('git', ['commit', '-m', `ppg: merge ${wt.name} (${wt.branch})`], { cwd: projectRoot });
```
This is inherent to git's squash merge workflow — `git merge --squash` stages but doesn't commit. No optimization possible here; this is correct.

---

## 4. Kill Workflow — Operation Inventory

### Single agent kill (`killAgent`):

| # | Command | Source |
|---|---------|--------|
| 1 | `tmux send-keys -t <target> C-c` | `sendCtrlC()` |
| 2 | `setTimeout(2000)` | hard 2-second wait |
| 3 | `tmux display-message -t <target> -p <format>` | `getPaneInfo()` |
| 4 | `tmux kill-pane -t <target>` (conditional) | `killPane()` |

### Identified Issues

#### Issue 14: Hard 2-second wait in `killAgent`
**File**: `src/core/agent.ts:173`
```typescript
await new Promise((resolve) => setTimeout(resolve, 2000));
```
After sending Ctrl-C, there's a fixed 2-second wait before checking if the pane is still alive. This is the single largest latency in the kill path.

**Fix**: Use a polling approach — check every 200ms for up to 2 seconds. If the process exits early (common case), the kill completes faster:
```typescript
for (let i = 0; i < 10; i++) {
  await new Promise(resolve => setTimeout(resolve, 200));
  const paneInfo = await getPaneInfo(agent.tmuxTarget);
  if (!paneInfo || paneInfo.isDead) return;
}
// Still alive after 2s, force kill
await tmux.killPane(agent.tmuxTarget);
```

**Estimated savings**: 0-1800ms per agent kill (depends on how fast the agent responds to Ctrl-C).

#### Issue 15: Sequential kills in `killAllAgents` and `killWorktreeAgents`
**File**: `src/commands/kill.ts:119-127`
When killing all agents, each is killed sequentially. With the 2-second wait per agent, killing 5 agents takes ~10 seconds minimum.

**Fix**: Kill agents in parallel with `Promise.all`. The Ctrl-C signals and subsequent checks are independent.

**Estimated savings**: With 5 agents: from ~10s to ~2s.

---

## 5. Summary of Optimization Opportunities

### High Impact (significant user-perceived improvement)

| # | Optimization | Workflow | Savings |
|---|-------------|----------|---------|
| 15 | Parallelize agent kills | kill --all | Seconds (N × 2s → 2s) |
| 14 | Poll instead of fixed 2s wait | kill | 0-1.8s per agent |
| 7 | Parallelize status checks | status | ~100ms with 10 agents |
| 10 | Batch tmux queries per window | status (polling) | N calls → 1 per window |
| 6 | Fire-and-forget `openTerminalWindow` | spawn | 100-500ms |

### Medium Impact (measurable improvement)

| # | Optimization | Workflow | Savings |
|---|-------------|----------|---------|
| 5 | Parallelize env setup with tmux setup | spawn | 20-50ms |
| 11 | Reduce manifest lock cycles in merge | merge | 20-40ms |
| 1 | Combine `send-keys` into single call | spawn | ~10ms per agent |
| 4 | Parallelize env file copies | spawn | ~5-10ms |

### Low Impact (marginal improvement, code quality)

| # | Optimization | Workflow | Savings |
|---|-------------|----------|---------|
| 9 | Read-only status check (skip write when unchanged) | status --watch | Reduced lock contention |
| 2 | Cache session name instead of re-reading manifest | spawn | ~2ms |
| 3 | Attempt-create instead of check-then-create for session | spawn | ~5ms |
| 8 | Remove redundant `fileExists` re-checks | status | ~0.2ms per agent |
| 12 | Parallelize killWindow + teardownEnv | merge | ~5ms |

---

## 6. Race Conditions and Reliability Concerns

### Concern A: `refreshAllAgentStatuses` mutates manifest in-place
**File**: `src/core/agent.ts:135-166`
The function directly mutates the manifest object passed to it. When called inside `updateManifest`, this is fine because the lock protects it. But if called outside a lock (which doesn't happen currently), it would be a race condition. Current code is safe.

### Concern B: Status polling during spawn
If `status --watch` is running while `spawn` is executing, they both use `updateManifest` with the file lock. The lock has retries (5 retries, 100-1000ms backoff), so they shouldn't deadlock, but spawn could be delayed by ~100ms waiting for a status poll to finish writing.

### Concern C: `killAgent` + manifest update isn't atomic
**File**: `src/commands/kill.ts:46-55`
The agent is killed (Ctrl-C + wait + kill pane), then the manifest is updated. If the process crashes between kill and manifest update, the manifest shows the agent as "running" but it's actually dead. The status refresh would eventually detect it as "lost" via `getPaneInfo` returning null, so this self-heals.

### Concern D: Node.js event loop blocking during heavy polling
With `status --watch` at 2-second intervals, if there are many agents, the sequential status checks could take longer than 2 seconds, causing intervals to stack. The `setInterval` would keep firing. There's no guard against overlapping polls.

**Fix**: Use a self-scheduling `setTimeout` instead of `setInterval`:
```typescript
async function poll() {
  // ... do work ...
  setTimeout(poll, 2000);
}
poll();
```

---

## 7. Recommended Implementation Priority

1. **Parallelize agent kills** (#15) — Biggest user-facing pain point. Simple `Promise.all` wrapper.
2. **Poll-based kill wait** (#14) — Reduces kill latency dramatically. Simple loop.
3. **Parallelize status checks** (#7) — Important for conductor polling. Simple `Promise.all`.
4. **Batch tmux queries** (#10) — Important for status polling at scale. Use `list-panes` per window.
5. **Fire-and-forget Terminal.app** (#6) — One-line change, immediate spawn feel.
6. **Parallelize env + tmux setup** (#5) — Moderate complexity, solid savings.
7. **Reduce manifest lock cycles** (#11) — Moderate refactor, reduces I/O during merge.
8. **Combine send-keys** (#1) — Trivial fix, small gain per spawn.



---

## Agent 3: Manifest Locking, File I/O & Process Spawning

*Agent ID: `ag-3jjbas28`*

# Result: ag-3jjbas28

## Summary
Comprehensive performance audit of ppg-cli's manifest locking, file I/O patterns, and process spawning. Analyzed every command path, identified redundant reads/writes, sequential bottlenecks, and scaling concerns.

## Changes
No code files changed — this is a research/analysis deliverable.

## Notes

---

# Performance Audit: Manifest Locking, File I/O, and Process Spawning

## 1. File I/O Audit: Every Read/Write per Command Path

### `ppg init`
| Operation | File | Type | Notes |
|-----------|------|------|-------|
| `execa('git', ['rev-parse', ...])` | — | Process | Repo root detection |
| `execa('tmux', ['-V'])` | — | Process | Tmux check |
| `fs.mkdir` × 5 | `.pg/`, `results/`, `logs/`, `templates/`, `prompts/` | Write | Sequential, could be `Promise.all` |
| `fs.writeFile` | `config.yaml` | Write | Via `writeDefaultConfig` |
| `writeManifest` → `write-file-atomic` | `manifest.json` | Write | Atomic write |
| `fs.readFile` | `.gitignore` | Read | |
| `fs.appendFile` | `.gitignore` | Write | |
| `fs.access` | `templates/default.md` | Read | Existence check |
| `fs.writeFile` | `templates/default.md` | Write | Conditional |

**Total**: 2 process spawns, 2 reads, 6-8 writes. **Acceptable** — one-time setup.

### `ppg spawn` (new worktree)
| Operation | File | Type | Notes |
|-----------|------|------|-------|
| `execa('git', ['rev-parse', ...])` | — | Process | `getRepoRoot()` |
| `fs.readFile` | `config.yaml` | Read | `loadConfig()` |
| `fs.readFile` + `JSON.parse` | `manifest.json` | Read | Validation read (line 37) |
| `fs.readFile` (optional) | prompt file | Read | If `--prompt-file` |
| `fs.readdir` (optional) | templates dir | Read | If `--template` |
| `execa('git', ['branch', ...])` | — | Process | `getCurrentBranch()` |
| `execa('git', ['worktree', 'add', ...])` | — | Process | Create worktree |
| `fs.access` × N | env files | Read | Existence check per env file |
| `fs.copyFile` × N | env files | Write | Copy per env file |
| `fs.access` | `node_modules` source | Read | |
| `fs.lstat` | `node_modules` dest | Read | |
| `fs.symlink` | `node_modules` | Write | |
| `fs.readFile` + `JSON.parse` | `manifest.json` | Read | **2nd read** for `ensureSession` |
| `execa('tmux', ['has-session', ...])` | — | Process | |
| `execa('tmux', ['new-session', ...])` | — | Process | Conditional |
| `execa('tmux', ['new-window', ...])` | — | Process | |
| Per agent × count: | | | |
| `fs.writeFile` | `prompts/{agentId}.md` | Write | Prompt file |
| `execa('tmux', ['send-keys', ...])` × 2 | — | Process | Text + Enter |
| `proper-lockfile.lock` | `manifest.json.lock` | Lock | |
| `fs.readFile` + `JSON.parse` | `manifest.json` | Read | **3rd read** inside `updateManifest` |
| `write-file-atomic` | `manifest.json` | Write | |
| `proper-lockfile.unlock` | `manifest.json.lock` | Unlock | |
| `execa('osascript', [...])` | — | Process | Terminal.app open |

**Total**: ~8-10 process spawns, 5+ file reads (3 manifest reads), 4+ writes.

**KEY FINDING**: The manifest is read 3 times during spawn:
1. Line 37: validation read (`readManifest`) — just to confirm init
2. Line 117: `readManifest` for session name
3. Inside `updateManifest` at line 180: lock → read → write → unlock

Reads 1 and 2 are **completely redundant**. The session name from read 2 could come from the config. The validation read at line 37 could be deferred to the `updateManifest` call.

### `ppg status`
| Operation | File | Type | Notes |
|-----------|------|------|-------|
| `execa('git', ['rev-parse', ...])` | — | Process | `getRepoRoot()` |
| `proper-lockfile.lock` | `manifest.json.lock` | Lock | |
| `fs.readFile` + `JSON.parse` | `manifest.json` | Read | Inside `updateManifest` |
| Per agent: `fs.access` | result file | Read | 1-3 checks per agent via `checkAgentStatus` |
| Per agent: `execa('tmux', ['display-message', ...])` | — | Process | `getPaneInfo()` |
| Per worktree: `fs.access` | worktree path | Read | Directory existence |
| `write-file-atomic` + `JSON.stringify` | `manifest.json` | Write | |
| `proper-lockfile.unlock` | `manifest.json.lock` | Unlock | |

**Total**: 1 + N agent process spawns, 1 + 3N file reads (worst case), 1 write.

**KEY FINDING**: With `--watch`, this entire cycle repeats every **2 seconds**. At 50 agents:
- 50 `tmux display-message` process spawns per poll
- Up to 150 `fs.access` calls per poll (3 checks in worst case for status signal stack)
- Full `JSON.parse` + `JSON.stringify` cycle per poll

### `ppg aggregate`
| Operation | File | Type | Notes |
|-----------|------|------|-------|
| Same as status (refresh) | — | — | `updateManifest` + `refreshAllAgentStatuses` |
| Per completed agent: `fs.readFile` | result file | Read | Sequential loop |
| Per failed agent (no result): `execa('tmux', ['capture-pane', ...])` | — | Process | Fallback |

**KEY FINDING**: Result file reads are **sequential** (line 49-63 in aggregate.ts). With 20 completed agents, this is 20 sequential file reads that could be parallelized.

### `ppg merge`
| Operation | File | Type | Notes |
|-----------|------|------|-------|
| `updateManifest` | manifest | Lock+Read+Write | Status refresh |
| `updateManifest` | manifest | Lock+Read+Write | Set `merging` |
| `execa('git', ['merge', ...])` | — | Process | |
| `execa('git', ['commit', ...])` | — | Process | Squash only |
| `updateManifest` | manifest | Lock+Read+Write | Set `merged` |
| `execa('tmux', ['kill-window', ...])` | — | Process | |
| `fs.lstat` + `fs.unlink` | `node_modules` symlink | Read+Write | Teardown |
| `execa('git', ['worktree', 'remove', ...])` | — | Process | |
| `execa('git', ['branch', '-D', ...])` | — | Process | |
| `updateManifest` | manifest | Lock+Read+Write | Set `cleaned` |

**CRITICAL FINDING**: Merge calls `updateManifest` **4 times** (lines 23, 56, 79, 123). Each is a full lock → read → JSON.parse → update → JSON.stringify → atomic write → unlock cycle. On error path, it's still 3 calls (lines 23, 56, 89).

These 4 calls could be consolidated to 2 (one for status refresh + set merging, one for final state).

### `ppg kill --all --remove` (worst case)
| Operation | File | Type | Notes |
|-----------|------|------|-------|
| `readManifest` | manifest | Read | 1 |
| Per agent: `killAgent` → `execa` + 2s sleep + `execa` | — | Process | Sequential! |
| `updateManifest` | manifest | Lock+Read+Write | 1 |
| Per worktree: `readManifest` | manifest | Read | **Redundant!** (line 160) |
| Per worktree: `tmux.killWindow` | — | Process | |
| Per worktree: teardown | — | Read+Write | |
| Per worktree: `removeWorktree` | — | Process ×2 | worktree remove + branch delete |
| Per worktree: `updateManifest` | manifest | Lock+Read+Write | Per-worktree update |

**CRITICAL FINDING**: `removeWorktreeCleanup` (line 159) calls `readManifest` THEN later calls `updateManifest` — the read is wasted because `updateManifest` reads again. With 10 worktrees: 10 extra manifest reads + 10 separate lock/unlock cycles when a single `updateManifest` at the end could batch all status updates.

The kill flow is also fully **sequential** — agents are killed one-by-one with a 2-second sleep each. Killing 10 agents = ~20+ seconds of mandatory waiting.

---

## 2. Manifest Lock Analysis

### Lock Configuration
```typescript
{
  stale: 10_000,      // 10 seconds
  retries: {
    retries: 5,
    minTimeout: 100,   // 100ms initial backoff
    maxTimeout: 1000,  // 1 second max backoff
  }
}
```

### Analysis

**Stale timeout (10s)**: **Appropriate but with a caveat.** The longest operation inside `updateManifest` is `refreshAllAgentStatuses`, which spawns N tmux processes sequentially. At 50 agents, each `getPaneInfo` takes ~20-50ms, so refresh takes 1-2.5 seconds. With 100+ agents, this approaches the 10s stale timeout, which would cause spurious lock steals.

**Retry configuration**: Adequate for typical contention. The exponential backoff (100ms → 1000ms over 5 retries) covers ~3.1 seconds of total wait, which is fine for short-held locks but may fail during heavy status refresh operations.

### Contention Points

1. **`ppg status --watch` vs any other command**: The status watch loop acquires the manifest lock every 2 seconds. If another command (like `ppg merge`) tries to run during this window, it faces contention.

2. **Conductor mode polling**: A conductor calling `ppg status --json` every 5 seconds from a subprocess also contends with the lock file.

3. **Merge during watch**: `ppg merge` acquires the lock 4 times. Combined with a concurrent `ppg status --watch`, this is 4 contention windows.

### Recommendations

**a) Read-only operations should not take locks.** `readManifest` is currently lock-free, which is correct. But `statusCommand` wraps `refreshAllAgentStatuses` in `updateManifest` (which locks), even though the write is just a status cache update. If the write fails, no data is lost — the status will be recalculated next time. Consider: read manifest → refresh statuses → try to write back (best-effort, no lock for the status-only update), or use a short-lived optimistic lock.

**b) Batch manifest updates.** The merge command's 4 separate `updateManifest` calls should be reduced to 2. The kill --all command's per-worktree cleanup loop should accumulate state changes and commit them in one `updateManifest`.

**c) Separate status cache from manifest.** Agent statuses are ephemeral/derived data (can be recalculated from tmux + result files). Consider storing live status separately from the manifest's structural data. This eliminates lock contention for status polling entirely.

---

## 3. Process Spawn Overhead Analysis

### Current Patterns

Every tmux interaction is a separate `execa` call. The `sendKeys` function spawns **two** processes per invocation (one for the text, one for Enter).

### Spawn Counts per Command

| Command | Minimum execa calls | At scale (N agents) |
|---------|-------------------|---------------------|
| `ppg init` | 2 | 2 |
| `ppg spawn` (1 agent) | ~8 | 6 + 2N |
| `ppg status` | 2 + N | 2 + N (per poll) |
| `ppg kill --all` | 2 + 3N | 2 + 3N (2s sleep per agent) |
| `ppg merge` | ~8 | ~8 |
| `ppg aggregate` | 2 + N_failed | 2 + N_completed + N_failed |

### Specific Bottlenecks

**a) `sendKeys` double-spawn (tmux.ts:59-63)**
```typescript
await execa('tmux', ['send-keys', '-t', target, '-l', command]);
await execa('tmux', ['send-keys', '-t', target, 'Enter']);
```
This is 2 sequential process spawns. Tmux supports sending literal text + Enter in a single command:
```typescript
await execa('tmux', ['send-keys', '-t', target, command, 'Enter']);
```
However, the `-l` flag (literal) is intentional to avoid tmux key binding interpretation. The fix is to drop `-l` and append `Enter` as a separate key name — tmux `send-keys` without `-l` interprets `Enter` as the key, and the command text can be passed without `-l` as long as it doesn't start with special tmux key names. **Safer approach**: concatenate a newline into the literal text:
```typescript
await execa('tmux', ['send-keys', '-t', target, '-l', command + '\n']);
```
This eliminates 1 process spawn per agent spawn.

**b) Sequential agent killing (agent.ts:168-181)**
```typescript
await tmux.sendCtrlC(agent.tmuxTarget);
await new Promise((resolve) => setTimeout(resolve, 2000));
const paneInfo = await getPaneInfo(agent.tmuxTarget);
```
The 2-second sleep is per agent, sequential. For `kill --all` with 10 agents, that's 20+ seconds. This should:
1. Send Ctrl-C to ALL agents first (parallel)
2. Wait 2 seconds once
3. Check which are still alive (parallel)
4. Kill remaining panes (parallel)

**c) Status refresh is sequential (agent.ts:139-166)**
`refreshAllAgentStatuses` loops through all agents sequentially, spawning a tmux process for each. With `Promise.all` or `Promise.allSettled`, this becomes parallel:
```typescript
const checks = Object.values(wt.agents).map(agent =>
  checkAgentStatus(agent, projectRoot).then(result => ({ agent, ...result }))
);
const results = await Promise.allSettled(checks);
```

**d) tmux command batching**
Multiple tmux queries (like checking N pane statuses) could be batched into a single `list-panes` call per session:
```typescript
// Instead of N getPaneInfo calls:
const allPanes = await execa('tmux', [
  'list-panes', '-s', '-t', sessionName,
  '-F', '#{pane_id}|#{pane_pid}|#{pane_current_command}|#{pane_dead}|#{pane_dead_status}|#{window_index}'
]);
```
This replaces N process spawns with 1. The `listPanes` function already exists (tmux.ts:98-118) but targets a single window. A session-wide variant would be trivially simple.

---

## 4. Scaling Projections

### Manifest Size Growth

Each `WorktreeEntry` ≈ 200 bytes base + ~180 bytes per agent (truncated prompt at 500 chars is the largest field).

| Worktrees | Agents/WT | Manifest Size | JSON.parse Time | JSON.stringify Time |
|-----------|-----------|---------------|-----------------|---------------------|
| 5 | 1 | ~3 KB | <1ms | <1ms |
| 20 | 1 | ~10 KB | <1ms | <1ms |
| 50 | 2 | ~40 KB | ~1ms | ~1ms |
| 100 | 3 | ~100 KB | ~2ms | ~2ms |
| 500 | 3 | ~500 KB | ~5-10ms | ~5-10ms |

**JSON parse/stringify is NOT a bottleneck** even at 500 worktrees. V8's JSON parser handles MB-scale data in milliseconds.

### Status Polling at Scale

| Agents | tmux spawns/poll | fs.access/poll | Lock hold time | Poll cost |
|--------|-----------------|----------------|----------------|-----------|
| 10 | 10 | 10-30 | ~300ms | ~500ms |
| 50 | 50 | 50-150 | ~1.5s | ~2.5s |
| 100 | 100 | 100-300 | ~3s | ~5s |
| 200 | 200 | 200-600 | ~6s | ~10s |

**At 100+ agents, status polling exceeds the 2-second watch interval** and approaches the 10-second lock stale timeout. This is the primary scaling bottleneck.

### Breakpoint

The manifest.json single-file approach breaks down operationally around **100-200 agents** due to:
1. Lock contention during status refresh (lock held for seconds)
2. Status polling cost exceeding poll interval
3. Sequential tmux process spawning

The data model itself (JSON structure) is fine to 1000+ entries.

---

## 5. Concrete Optimization Recommendations

### Priority 1 — High Impact, Low Effort

**1a. Parallelize `refreshAllAgentStatuses`** (agent.ts:135-166)
Replace the sequential loop with `Promise.all`. Expected speedup: N× for N agents.
```typescript
export async function refreshAllAgentStatuses(manifest, projectRoot) {
  const allAgents = Object.values(manifest.worktrees).flatMap(wt =>
    Object.values(wt.agents).map(agent => ({ wt, agent }))
  );

  const results = await Promise.all(
    allAgents.map(({ agent }) => checkAgentStatus(agent, projectRoot))
  );

  allAgents.forEach(({ wt, agent }, i) => {
    const { status, exitCode } = results[i];
    if (status !== agent.status) {
      agent.status = status;
      if (exitCode !== undefined) agent.exitCode = exitCode;
      if (['completed', 'failed', 'lost'].includes(status) && !agent.completedAt) {
        agent.completedAt = new Date().toISOString();
      }
    }
  });

  // Parallel worktree existence checks
  await Promise.all(Object.values(manifest.worktrees).map(async wt => {
    if (wt.status === 'active') {
      const exists = await fileExists(wt.path);
      if (!exists) {
        wt.status = 'cleaned';
        for (const agent of Object.values(wt.agents)) {
          if (!['completed', 'failed', 'killed'].includes(agent.status)) {
            agent.status = 'lost';
            if (!agent.completedAt) agent.completedAt = new Date().toISOString();
          }
        }
      }
    }
  }));

  return manifest;
}
```

**1b. Batch tmux pane queries** — Add a session-wide `listAllPanes` function that replaces N `getPaneInfo` calls with 1 `list-panes -s` call.
```typescript
export async function listAllSessionPanes(session: string): Promise<Map<string, PaneInfo>> {
  const result = await execa('tmux', [
    'list-panes', '-s', '-t', session,
    '-F', '#{pane_id}|#{pane_pid}|#{pane_current_command}|#{pane_dead}|#{pane_dead_status}',
  ]);
  const map = new Map<string, PaneInfo>();
  for (const line of result.stdout.trim().split('\n').filter(Boolean)) {
    const [paneId, panePid, currentCommand, dead, deadStatus] = line.split('|');
    map.set(paneId, { paneId, panePid, currentCommand, isDead: dead === '1', deadStatus: deadStatus ? parseInt(deadStatus, 10) : undefined });
  }
  return map;
}
```
Then `refreshAllAgentStatuses` fetches all pane info in one call and looks up per agent. This changes status polling from O(N) process spawns to O(1).

**1c. Eliminate redundant manifest reads in `spawn`** (spawn.ts)
- Remove the validation `readManifest` at line 37 — let `updateManifest` at line 180 handle ENOENT
- Pass `sessionName` from config instead of reading manifest at line 117

### Priority 2 — Medium Impact, Medium Effort

**2a. Reduce `merge` from 4 to 2 `updateManifest` calls**
Combine the status-refresh + set-merging into one call. Combine set-merged + set-cleaned into one call (after cleanup succeeds).

**2b. Parallel agent killing**
```typescript
export async function killAgents(agents: AgentEntry[]): Promise<void> {
  // Phase 1: Send Ctrl-C to all
  await Promise.all(agents.map(a => tmux.sendCtrlC(a.tmuxTarget).catch(() => {})));
  // Phase 2: Wait once
  await new Promise(r => setTimeout(r, 2000));
  // Phase 3: Check and force-kill remaining
  await Promise.all(agents.map(async a => {
    const info = await getPaneInfo(a.tmuxTarget);
    if (info && !info.isDead) await tmux.killPane(a.tmuxTarget);
  }));
}
```

**2c. Batch `removeWorktreeCleanup` in kill --all**
Instead of calling `removeWorktreeCleanup` per worktree (each does `readManifest` + `updateManifest`), collect all worktree IDs and do one final `updateManifest`.

**2d. Parallelize result file reads in `aggregate`**
```typescript
const results = await Promise.all(
  agentsToCollect.map(({ wt, agent }) =>
    collectAgentResult(agent, projectRoot).then(content => ({
      agentId: agent.id, worktreeId: wt.id, ...
    }))
  )
);
```

### Priority 3 — Future Scaling

**3a. Separate status cache from manifest**
Create `.pg/status-cache.json` for ephemeral status data. The manifest only stores structural/configuration data. Status polling writes to the cache without locking the manifest. This eliminates all lock contention for the most frequent operation.

**3b. Read-only manifest access without locking**
Status command and other read-heavy commands should not need locks. Only commands that modify structural manifest data (spawn, merge, kill) need locks. Status updates are idempotent and can use optimistic concurrency or a separate file.

**3c. `sendKeys` single-process optimization**
```typescript
// Replace two execa calls with one
await execa('tmux', ['send-keys', '-t', target, '-l', command + '\n']);
```
Saves 1 process spawn per agent spawn. Minor but free.

**3d. Parallelize `fs.mkdir` in init**
```typescript
await Promise.all(dirs.map(dir => fs.mkdir(dir, { recursive: true })));
```
Minor — init is one-time, but it's a free fix.

---

## Summary of Expected Impact

| Optimization | Effort | Impact at 10 agents | Impact at 50 agents |
|-------------|--------|---------------------|---------------------|
| Parallel status refresh | Low | ~3× faster | ~10× faster |
| Batch tmux queries | Medium | ~5× fewer spawns | ~25× fewer spawns |
| Remove redundant reads | Low | ~30% fewer I/O | ~30% fewer I/O |
| Reduce merge lock calls | Low | 2× fewer locks | 2× fewer locks |
| Parallel agent killing | Low | 10× faster kill | 50× faster kill |
| Parallel aggregate reads | Low | ~2× faster | ~5× faster |
| Separate status cache | Medium | Eliminates contention | Eliminates contention |

The single highest-impact change is **batching tmux pane queries into one `list-panes -s` call** combined with **parallelizing `refreshAllAgentStatuses`**. Together, these transform status polling from O(N) sequential process spawns to O(1), which directly enables scaling to 100+ agents.


