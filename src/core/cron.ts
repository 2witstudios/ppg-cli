import fs from 'node:fs/promises';
import path from 'node:path';
import { execa } from 'execa';
import { loadSchedules, getNextRun } from './schedule.js';
import { cronLogPath, cronPidPath, logsDir } from '../lib/paths.js';
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

  const schedules = await loadSchedules(projectRoot);
  const states: ScheduleState[] = schedules.map((entry) => ({
    entry,
    nextRun: getNextRun(entry.cron),
  }));

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
    const now = new Date();
    for (const state of states) {
      if (now >= state.nextRun) {
        await triggerSchedule(state, projectRoot);
        // Advance to next run time
        state.nextRun = getNextRun(state.entry.cron);
        state.lastTriggered = now;
        await logCron(projectRoot, `  ${state.entry.name}: next run at ${state.nextRun.toISOString()}`);
      }
    }
  };

  // Run immediately, then on interval
  await tick();
  setInterval(tick, CHECK_INTERVAL_MS);

  // Keep alive
  await new Promise(() => {});
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
  const pidPath = cronPidPath(projectRoot);
  try {
    const pid = parseInt(await fs.readFile(pidPath, 'utf-8'), 10);
    // Check if process is alive (signal 0 doesn't send a signal, just checks)
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export async function getCronPid(projectRoot: string): Promise<number | null> {
  const pidPath = cronPidPath(projectRoot);
  try {
    const pid = parseInt(await fs.readFile(pidPath, 'utf-8'), 10);
    process.kill(pid, 0);
    return pid;
  } catch {
    return null;
  }
}

export async function readCronLog(projectRoot: string, lines: number = 20): Promise<string[]> {
  const logPath = cronLogPath(projectRoot);
  try {
    const content = await fs.readFile(logPath, 'utf-8');
    const allLines = content.trim().split('\n').filter(Boolean);
    return allLines.slice(-lines);
  } catch {
    return [];
  }
}
