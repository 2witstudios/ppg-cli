# Cron Scheduling Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add cron/schedule ability so users can define recurring schedules that trigger ppg spawn/swarm runs automatically.

**Architecture:** Schedules defined in `.ppg/schedules.yaml`. A long-running daemon process runs in a tmux window, checks cron expressions every 30s, and triggers `ppg spawn` or `ppg swarm` via execa. State tracked via a PID file and cron log.

**Tech Stack:** cron-parser (npm), existing tmux/spawn/swarm infrastructure, execa for subprocess spawning.

---

### Task 1: Install cron-parser dependency

**Step 1:** Install cron-parser
```bash
npm install cron-parser
```

**Step 2:** Verify it installed correctly
```bash
node -e "import('cron-parser').then(m => console.log('OK'))"
```

**Step 3:** Commit
```bash
git add package.json package-lock.json
git commit -m "chore: add cron-parser dependency"
```

---

### Task 2: Add path helpers and schedule types

**Files:**
- Modify: `src/lib/paths.ts`
- Create: `src/types/schedule.ts`

**Step 1:** Add path helpers to `src/lib/paths.ts`:
- `schedulesPath(projectRoot)` → `.ppg/schedules.yaml`
- `cronLogPath(projectRoot)` → `.ppg/logs/cron.log`
- `cronPidPath(projectRoot)` → `.ppg/cron.pid`

**Step 2:** Create `src/types/schedule.ts` with:
- `ScheduleEntry` — name, swarm?, prompt?, cron, vars?
- `SchedulesConfig` — schedules array

**Step 3:** Typecheck
```bash
npm run typecheck
```

**Step 4:** Commit

---

### Task 3: Core schedule loader

**Files:**
- Create: `src/core/schedule.ts`

**Step 1:** Implement `loadSchedules(projectRoot)`:
- Read `.ppg/schedules.yaml`
- Parse YAML, validate entries
- Each entry must have `name`, `cron`, and exactly one of `swarm` or `prompt`
- Return `ScheduleEntry[]`

**Step 2:** Implement `validateCronExpression(expr)`:
- Use cron-parser to validate
- Throw PpgError on invalid expressions

**Step 3:** Implement `getNextRun(cronExpr)`:
- Return next Date for given cron expression

**Step 4:** Typecheck + test

---

### Task 4: Cron daemon logic

**Files:**
- Create: `src/core/cron.ts`

**Step 1:** Implement `runCronDaemon(projectRoot)`:
- Load schedules
- Write PID file
- Set up 30s interval
- On each tick: check each schedule's next run time
- If past due: trigger via execa (`ppg swarm <name>` or `ppg spawn --template <name>`)
- Log all activity to `.ppg/logs/cron.log`
- Handle SIGTERM for clean shutdown (remove PID file)

**Step 2:** Implement `logCron(projectRoot, message)`:
- Append timestamped line to cron log

**Step 3:** Implement `isCronRunning(projectRoot)`:
- Check PID file exists and process is alive

---

### Task 5: CLI commands

**Files:**
- Create: `src/commands/cron.ts`
- Modify: `src/cli.ts`

**Step 1:** Implement commands:
- `cronStartCommand` — ensure session, create tmux window, run `ppg cron _daemon`
- `cronStopCommand` — find and kill cron tmux window
- `cronListCommand` — load schedules, show table with name/cron/next-run
- `cronStatusCommand` — show running state + tail recent log entries
- `cronDaemonCommand` — internal: runs the daemon loop (not user-facing)

**Step 2:** Register in `src/cli.ts`:
- Add `ppg cron` command group with subcommands: start, stop, list, status
- Hidden `_daemon` subcommand

**Step 3:** Typecheck + test

---

### Task 6: Tests

**Files:**
- Create: `src/core/schedule.test.ts`

Test schedule loading, cron expression validation, next-run calculation.

---

### Task 7: Verify and ship

**Step 1:** `npm run typecheck`
**Step 2:** `npm test`
**Step 3:** Commit all changes
**Step 4:** Push and create PR
