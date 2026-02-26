import fs from 'node:fs/promises';
import { getRepoRoot } from '../core/worktree.js';
import { readManifest } from '../core/manifest.js';
import { loadSchedules, getNextRun, formatCronHuman } from '../core/schedule.js';
import { runCronDaemon, isCronRunning, getCronPid, readCronLog } from '../core/cron.js';
import * as tmux from '../core/tmux.js';
import { cronPidPath, manifestPath } from '../lib/paths.js';
import { PpgError, NotInitializedError } from '../lib/errors.js';
import { output, outputError, formatTable, info, success, warn } from '../lib/output.js';
import type { Column } from '../lib/output.js';

export interface CronOptions {
  json?: boolean;
}

export interface CronStatusOptions {
  lines?: number;
  json?: boolean;
}

const CRON_WINDOW_NAME = 'ppg-cron';

export async function cronStartCommand(options: CronOptions): Promise<void> {
  const projectRoot = await getRepoRoot();
  await requireInit(projectRoot);

  // Check if already running
  if (await isCronRunning(projectRoot)) {
    const pid = await getCronPid(projectRoot);
    if (options.json) {
      output({ success: false, error: 'Cron daemon is already running', pid }, true);
    } else {
      warn(`Cron daemon is already running (PID: ${pid})`);
    }
    return;
  }

  // Verify schedules can be loaded before starting
  const schedules = await loadSchedules(projectRoot);
  if (schedules.length === 0) {
    throw new PpgError('No schedules defined in .ppg/schedules.yaml', 'INVALID_ARGS');
  }

  // Start daemon in a tmux window
  const manifest = await readManifest(projectRoot);
  const sessionName = manifest.sessionName;
  await tmux.ensureSession(sessionName);

  const windowTarget = await tmux.createWindow(sessionName, CRON_WINDOW_NAME, projectRoot);
  const command = `ppg cron _daemon`;
  await tmux.sendKeys(windowTarget, command);

  if (options.json) {
    output({
      success: true,
      tmuxWindow: windowTarget,
      scheduleCount: schedules.length,
    }, true);
  } else {
    success(`Cron daemon started in tmux window: ${windowTarget}`);
    info(`${schedules.length} schedule(s) loaded`);
    info(`Attach: tmux select-window -t ${windowTarget}`);
  }
}

export async function cronStopCommand(options: CronOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  const pid = await getCronPid(projectRoot);
  if (!pid) {
    if (options.json) {
      output({ success: false, error: 'Cron daemon is not running' }, true);
    } else {
      warn('Cron daemon is not running');
    }
    return;
  }

  // Kill the process
  try {
    process.kill(pid, 'SIGTERM');
  } catch {
    // Already dead
  }

  // Clean up PID file
  try {
    await fs.unlink(cronPidPath(projectRoot));
  } catch { /* already gone */ }

  // Try to kill the tmux window too
  try {
    const manifest = await readManifest(projectRoot);
    const windows = await tmux.listSessionWindows(manifest.sessionName);
    const cronWindow = windows.find((w) => w.name === CRON_WINDOW_NAME);
    if (cronWindow) {
      await tmux.killWindow(`${manifest.sessionName}:${cronWindow.index}`);
    }
  } catch { /* best effort */ }

  if (options.json) {
    output({ success: true, pid }, true);
  } else {
    success(`Cron daemon stopped (PID: ${pid})`);
  }
}

export async function cronListCommand(options: CronOptions): Promise<void> {
  const projectRoot = await getRepoRoot();
  await requireInit(projectRoot);

  const schedules = await loadSchedules(projectRoot);

  if (options.json) {
    const data = schedules.map((s) => ({
      name: s.name,
      type: s.swarm ? 'swarm' : 'prompt',
      target: s.swarm ?? s.prompt,
      cron: s.cron,
      nextRun: getNextRun(s.cron).toISOString(),
      vars: s.vars ?? {},
    }));
    output({ schedules: data }, true);
    return;
  }

  const columns: Column[] = [
    { header: 'NAME', key: 'name' },
    { header: 'TYPE', key: 'type' },
    { header: 'TARGET', key: 'target' },
    { header: 'CRON', key: 'cron' },
    { header: 'SCHEDULE', key: 'human' },
    { header: 'NEXT RUN', key: 'nextRun' },
  ];

  const rows = schedules.map((s) => ({
    name: s.name,
    type: s.swarm ? 'swarm' : 'prompt',
    target: s.swarm ?? s.prompt,
    cron: s.cron,
    human: formatCronHuman(s.cron),
    nextRun: getNextRun(s.cron).toLocaleString(),
  }));

  console.log(formatTable(rows, columns));
}

export async function cronStatusCommand(options: CronStatusOptions): Promise<void> {
  const projectRoot = await getRepoRoot();

  const running = await isCronRunning(projectRoot);
  const pid = running ? await getCronPid(projectRoot) : null;
  const recentLines = await readCronLog(projectRoot, options.lines ?? 20);

  if (options.json) {
    output({
      running,
      pid,
      recentLog: recentLines,
    }, true);
    return;
  }

  if (running) {
    success(`Cron daemon is running (PID: ${pid})`);
  } else {
    warn('Cron daemon is not running');
  }

  if (recentLines.length > 0) {
    console.log('\nRecent log:');
    for (const line of recentLines) {
      console.log(`  ${line}`);
    }
  } else {
    info('No cron log entries yet');
  }
}

export async function cronDaemonCommand(): Promise<void> {
  const projectRoot = await getRepoRoot();
  await requireInit(projectRoot);
  await runCronDaemon(projectRoot);
}

async function requireInit(projectRoot: string): Promise<void> {
  try {
    await fs.access(manifestPath(projectRoot));
  } catch {
    throw new NotInitializedError(projectRoot);
  }
}
