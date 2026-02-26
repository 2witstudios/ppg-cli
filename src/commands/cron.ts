import fs from 'node:fs/promises';
import YAML from 'yaml';
import { getRepoRoot } from '../core/worktree.js';
import { readManifest } from '../core/manifest.js';
import { loadSchedules, getNextRun, formatCronHuman, validateCronExpression } from '../core/schedule.js';
import { runCronDaemon, isCronRunning, getCronPid, readCronLog } from '../core/cron.js';
import * as tmux from '../core/tmux.js';
import { cronPidPath, manifestPath, schedulesPath, ppgDir } from '../lib/paths.js';
import { PpgError, NotInitializedError } from '../lib/errors.js';
import { output, formatTable, info, success, warn } from '../lib/output.js';
import type { Column } from '../lib/output.js';
import type { ScheduleEntry, SchedulesConfig } from '../types/schedule.js';

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

  // getCronPid already cleans up stale PID files
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

  // Clean up PID file (daemon cleanup handler may not have run yet)
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

export interface CronAddOptions {
  name: string;
  cron: string;
  swarm?: string;
  prompt?: string;
  var?: string[];
  project?: string;
  json?: boolean;
}

export async function cronAddCommand(options: CronAddOptions): Promise<void> {
  const projectRoot = options.project ?? await getRepoRoot();
  const json = options.json ?? false;

  // Validate: exactly one of swarm or prompt
  if (options.swarm && options.prompt) {
    throw new PpgError('Specify either --swarm or --prompt, not both', 'INVALID_ARGS');
  }
  if (!options.swarm && !options.prompt) {
    throw new PpgError('Must specify either --swarm or --prompt', 'INVALID_ARGS');
  }

  // Validate cron expression
  validateCronExpression(options.cron);

  // Ensure .ppg directory exists
  await fs.mkdir(ppgDir(projectRoot), { recursive: true });

  // Load existing schedules (or start with empty array if file doesn't exist)
  const filePath = schedulesPath(projectRoot);
  let schedules: ScheduleEntry[] = [];
  try {
    const raw = await fs.readFile(filePath, 'utf-8');
    const parsed = YAML.parse(raw) as SchedulesConfig | null;
    if (parsed && Array.isArray(parsed.schedules)) {
      schedules = parsed.schedules;
    }
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code !== 'ENOENT') {
      throw err;
    }
  }

  // Validate name is unique
  if (schedules.some((s) => s.name === options.name)) {
    throw new PpgError(`Schedule "${options.name}" already exists`, 'INVALID_ARGS');
  }

  // Build the new entry
  const entry: ScheduleEntry = {
    name: options.name,
    cron: options.cron,
  };
  if (options.swarm) {
    entry.swarm = options.swarm;
  }
  if (options.prompt) {
    entry.prompt = options.prompt;
  }
  if (options.var && options.var.length > 0) {
    const vars: Record<string, string> = {};
    for (const v of options.var) {
      const eq = v.indexOf('=');
      if (eq === -1) {
        throw new PpgError(`Invalid variable format: "${v}" — expected key=value`, 'INVALID_ARGS');
      }
      vars[v.slice(0, eq)] = v.slice(eq + 1);
    }
    entry.vars = vars;
  }

  // Append and write back
  schedules.push(entry);
  const config: SchedulesConfig = { schedules };
  await fs.writeFile(filePath, YAML.stringify(config), 'utf-8');

  if (json) {
    output({ success: true, schedule: entry }, true);
  } else {
    success(`Schedule "${options.name}" added`);
  }
}

export interface CronRemoveOptions {
  name: string;
  project?: string;
  json?: boolean;
}

export async function cronRemoveCommand(options: CronRemoveOptions): Promise<void> {
  const projectRoot = options.project ?? await getRepoRoot();
  const json = options.json ?? false;

  // Load existing schedules
  const filePath = schedulesPath(projectRoot);
  let schedules: ScheduleEntry[] = [];
  try {
    const raw = await fs.readFile(filePath, 'utf-8');
    const parsed = YAML.parse(raw) as SchedulesConfig | null;
    if (parsed && Array.isArray(parsed.schedules)) {
      schedules = parsed.schedules;
    }
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
      throw new PpgError(`Schedule "${options.name}" not found`, 'INVALID_ARGS');
    }
    throw err;
  }

  // Find and remove
  const before = schedules.length;
  const filtered = schedules.filter((s) => s.name !== options.name);
  if (filtered.length === before) {
    throw new PpgError(`Schedule "${options.name}" not found`, 'INVALID_ARGS');
  }

  // Write back (even if empty, keep the file with empty schedules array)
  const config: SchedulesConfig = { schedules: filtered };
  await fs.writeFile(filePath, YAML.stringify(config), 'utf-8');

  if (json) {
    output({ success: true, removed: options.name }, true);
  } else {
    success(`Schedule "${options.name}" removed`);
  }
}

async function requireInit(projectRoot: string): Promise<void> {
  try {
    await fs.access(manifestPath(projectRoot));
  } catch {
    throw new NotInitializedError(projectRoot);
  }
}
