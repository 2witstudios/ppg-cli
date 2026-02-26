import fs from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { execa } from 'execa';
import { loadSchedules, getNextRun } from './schedule.js';
import { cronLogPath, cronPidPath, logsDir, schedulesPath } from '../lib/paths.js';
import type { ScheduleEntry } from '../types/schedule.js';

const CHECK_INTERVAL_MS = 30_000;

interface ScheduleState {
  entry: ScheduleEntry;
  nextRun: Date;
  lastTriggered?: Date;
}

export async function runCronDaemon(projectRoot: string): Promise<void> {
  const pidPath = cronPidPath(projectRoot);

  // Write PID file
  await fs.mkdir(path.dirname(pidPath), { recursive: true });
  await fs.writeFile(pidPath, String(process.pid), 'utf-8');

  // Ensure logs directory
  await fs.mkdir(logsDir(projectRoot), { recursive: true });

  await logCron(projectRoot, 'Cron daemon starting');

  let states = await loadScheduleStates(projectRoot);
  let lastConfigMtime = await getFileMtime(schedulesPath(projectRoot));

  await logCron(projectRoot, `Loaded ${states.length} schedule(s)`);
  for (const s of states) {
    await logCron(projectRoot, `  ${s.entry.name}: next run at ${s.nextRun.toISOString()}`);
  }

  // Clean shutdown on SIGTERM/SIGINT
  const cleanup = async () => {
    await logCron(projectRoot, 'Cron daemon stopping');
    try {
      await fs.unlink(pidPath);
    } catch { /* already gone */ }
    process.exit(0);
  };
  process.on('SIGTERM', cleanup);
  process.on('SIGINT', cleanup);

  // Main loop
  const tick = async () => {
    // Reload schedules if config file changed
    const currentMtime = await getFileMtime(schedulesPath(projectRoot));
    if (currentMtime !== lastConfigMtime) {
      try {
        states = await loadScheduleStates(projectRoot);
        lastConfigMtime = currentMtime;
        await logCron(projectRoot, `Reloaded schedules (${states.length} schedule(s))`);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        await logCron(projectRoot, `Failed to reload schedules: ${msg}`);
      }
    }

    const now = new Date();
    const due = states.filter((s) => now >= s.nextRun);
    // Fire all due schedules concurrently
    await Promise.allSettled(
      due.map(async (state) => {
        await triggerSchedule(state, projectRoot);
        state.nextRun = getNextRun(state.entry.cron);
        state.lastTriggered = now;
        await logCron(projectRoot, `  ${state.entry.name}: next run at ${state.nextRun.toISOString()}`);
      }),
    );
  };

  // Run immediately, then on interval
  await tick();
  setInterval(tick, CHECK_INTERVAL_MS);

  // Keep alive
  await new Promise(() => {});
}

async function loadScheduleStates(projectRoot: string): Promise<ScheduleState[]> {
  const schedules = await loadSchedules(projectRoot);
  return schedules.map((entry) => ({
    entry,
    nextRun: getNextRun(entry.cron),
  }));
}

async function getFileMtime(filePath: string): Promise<number> {
  try {
    const stat = await fs.stat(filePath);
    return stat.mtimeMs;
  } catch {
    return 0;
  }
}

async function triggerSchedule(state: ScheduleState, projectRoot: string): Promise<void> {
  const { entry } = state;
  await logCron(projectRoot, `Triggering schedule: ${entry.name}`);

  const varArgs: string[] = [];
  if (entry.vars) {
    for (const [key, value] of Object.entries(entry.vars)) {
      varArgs.push('--var', `${key}=${value}`);
    }
  }

  try {
    if (entry.swarm) {
      const args = ['swarm', entry.swarm, ...varArgs, '--json'];
      await logCron(projectRoot, `  Running: ppg ${args.join(' ')}`);
      const result = await execa('ppg', args, { cwd: projectRoot, reject: false });
      if (result.exitCode === 0) {
        await logCron(projectRoot, `  Success: ${entry.name} (swarm: ${entry.swarm})`);
      } else {
        await logCron(projectRoot, `  Failed: ${entry.name} — ${result.stderr || result.stdout}`);
      }
    } else if (entry.prompt) {
      const args = [
        'spawn',
        '--name', `cron-${entry.name}-${Date.now()}`,
        '--template', entry.prompt,
        ...varArgs,
        '--json',
      ];
      await logCron(projectRoot, `  Running: ppg ${args.join(' ')}`);
      const result = await execa('ppg', args, { cwd: projectRoot, reject: false });
      if (result.exitCode === 0) {
        await logCron(projectRoot, `  Success: ${entry.name} (prompt: ${entry.prompt})`);
      } else {
        await logCron(projectRoot, `  Failed: ${entry.name} — ${result.stderr || result.stdout}`);
      }
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    await logCron(projectRoot, `  Error triggering ${entry.name}: ${message}`);
  }
}

export async function logCron(projectRoot: string, message: string): Promise<void> {
  const logPath = cronLogPath(projectRoot);
  const timestamp = new Date().toISOString();
  const line = `[${timestamp}] ${message}\n`;

  // Also write to stdout so it's visible in the tmux pane
  process.stdout.write(line);

  try {
    await fs.appendFile(logPath, line, 'utf-8');
  } catch {
    // Log dir may not exist yet on first call — create and retry
    await fs.mkdir(logsDir(projectRoot), { recursive: true });
    await fs.appendFile(logPath, line, 'utf-8');
  }
}

export async function isCronRunning(projectRoot: string): Promise<boolean> {
  return (await getCronPid(projectRoot)) !== null;
}

export async function getCronPid(projectRoot: string): Promise<number | null> {
  const pidPath = cronPidPath(projectRoot);
  let raw: string;
  try {
    raw = await fs.readFile(pidPath, 'utf-8');
  } catch {
    return null;
  }
  const pid = parseInt(raw, 10);
  if (isNaN(pid)) {
    await cleanupPidFile(pidPath);
    return null;
  }
  try {
    // Signal 0 doesn't send a signal, just checks if process is alive
    process.kill(pid, 0);
    return pid;
  } catch {
    // Process is dead — clean up stale PID file
    await cleanupPidFile(pidPath);
    return null;
  }
}

async function cleanupPidFile(pidPath: string): Promise<void> {
  try {
    await fs.unlink(pidPath);
  } catch { /* already gone */ }
}

export async function readCronLog(projectRoot: string, lines: number = 20): Promise<string[]> {
  const logPath = cronLogPath(projectRoot);
  try {
    await fs.access(logPath);
  } catch {
    return [];
  }
  // Stream the file and keep only the last N lines to avoid loading large logs into memory
  const result: string[] = [];
  const rl = readline.createInterface({
    input: createReadStream(logPath, { encoding: 'utf-8' }),
    crlfDelay: Infinity,
  });
  for await (const line of rl) {
    if (!line) continue;
    result.push(line);
    if (result.length > lines) {
      result.shift();
    }
  }
  return result;
}
