import fs from 'node:fs/promises';
import YAML from 'yaml';
import { CronExpressionParser } from 'cron-parser';
import { schedulesPath } from '../lib/paths.js';
import { PpgError } from '../lib/errors.js';
import type { ScheduleEntry, SchedulesConfig } from '../types/schedule.js';

const SAFE_NAME = /^[\w-]+$/;

export async function loadSchedules(projectRoot: string): Promise<ScheduleEntry[]> {
  const filePath = schedulesPath(projectRoot);
  let raw: string;
  try {
    raw = await fs.readFile(filePath, 'utf-8');
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
      throw new PpgError('No schedules file found. Create .ppg/schedules.yaml first.', 'INVALID_ARGS');
    }
    throw err;
  }

  const parsed = YAML.parse(raw) as SchedulesConfig;
  if (!parsed || !Array.isArray(parsed.schedules)) {
    throw new PpgError('Invalid schedules.yaml: missing "schedules" array', 'INVALID_ARGS');
  }

  for (let i = 0; i < parsed.schedules.length; i++) {
    validateScheduleEntry(parsed.schedules[i], i);
  }

  return parsed.schedules;
}

function validateScheduleEntry(entry: ScheduleEntry, index: number): void {
  if (!entry.name || typeof entry.name !== 'string') {
    throw new PpgError(`schedules[${index}]: missing "name"`, 'INVALID_ARGS');
  }
  if (!SAFE_NAME.test(entry.name)) {
    throw new PpgError(
      `schedules[${index}]: invalid name "${entry.name}" — must be alphanumeric, hyphens, or underscores`,
      'INVALID_ARGS',
    );
  }
  if (!entry.cron || typeof entry.cron !== 'string') {
    throw new PpgError(`schedules[${index}]: missing "cron" expression`, 'INVALID_ARGS');
  }
  validateCronExpression(entry.cron, index);

  const hasSwarm = entry.swarm && typeof entry.swarm === 'string';
  const hasPrompt = entry.prompt && typeof entry.prompt === 'string';
  if (!hasSwarm && !hasPrompt) {
    throw new PpgError(`schedules[${index}]: must specify either "swarm" or "prompt"`, 'INVALID_ARGS');
  }
  if (hasSwarm && hasPrompt) {
    throw new PpgError(`schedules[${index}]: specify either "swarm" or "prompt", not both`, 'INVALID_ARGS');
  }
}

export function validateCronExpression(expr: string, index?: number): void {
  const prefix = index !== undefined ? `schedules[${index}]: ` : '';
  if (!expr || !expr.trim()) {
    throw new PpgError(`${prefix}invalid cron expression: "${expr}"`, 'INVALID_ARGS');
  }
  try {
    CronExpressionParser.parse(expr);
  } catch {
    throw new PpgError(`${prefix}invalid cron expression: "${expr}"`, 'INVALID_ARGS');
  }
}

export function getNextRun(cronExpr: string): Date {
  const expr = CronExpressionParser.parse(cronExpr);
  return expr.next().toDate();
}

export function formatCronHuman(cronExpr: string): string {
  // Basic human-readable descriptions for common patterns
  const parts = cronExpr.trim().split(/\s+/);
  if (parts.length !== 5) return cronExpr;

  const [min, hour, dom, mon, dow] = parts;

  if (min === '0' && hour !== '*' && dom === '*' && mon === '*' && dow === '*') {
    return `daily at ${hour}:00`;
  }
  if (min.startsWith('*/') && hour === '*' && dom === '*' && mon === '*' && dow === '*') {
    return `every ${min.slice(2)} minutes`;
  }
  if (min !== '*' && hour === '*' && dom === '*' && mon === '*' && dow === '*') {
    return `every hour at :${min.padStart(2, '0')}`;
  }
  if (dow !== '*' && dom === '*' && mon === '*') {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const dayName = days[Number(dow)] ?? dow;
    return `${dayName} at ${hour}:${min.padStart(2, '0')}`;
  }

  return cronExpr;
}
