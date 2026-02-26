import { describe, test, expect, vi, beforeEach } from 'vitest';
import { validateCronExpression, getNextRun, formatCronHuman } from './schedule.js';

describe('validateCronExpression', () => {
  test('given a valid cron expression, should not throw', () => {
    expect(() => validateCronExpression('0 2 * * *')).not.toThrow();
    expect(() => validateCronExpression('*/5 * * * *')).not.toThrow();
    expect(() => validateCronExpression('0 9 * * 1')).not.toThrow();
  });

  test('given an invalid cron expression, should throw PpgError', () => {
    expect(() => validateCronExpression('not a cron')).toThrow('invalid cron expression');
    expect(() => validateCronExpression('')).toThrow('invalid cron expression');
  });

  test('given an index, should include it in error message', () => {
    expect(() => validateCronExpression('bad', 2)).toThrow('schedules[2]:');
  });
});

describe('getNextRun', () => {
  test('given a valid cron expression, should return a future Date', () => {
    const next = getNextRun('*/5 * * * *');
    expect(next).toBeInstanceOf(Date);
    expect(next.getTime()).toBeGreaterThan(Date.now());
  });

  test('given a daily schedule, should return a Date within 24 hours', () => {
    const next = getNextRun('0 12 * * *');
    expect(next).toBeInstanceOf(Date);
    const hoursDiff = (next.getTime() - Date.now()) / (1000 * 60 * 60);
    expect(hoursDiff).toBeLessThanOrEqual(24);
  });
});

describe('formatCronHuman', () => {
  test('given daily at specific hour, should format as daily', () => {
    expect(formatCronHuman('0 2 * * *')).toBe('daily at 2:00');
  });

  test('given every N minutes, should format correctly', () => {
    expect(formatCronHuman('*/5 * * * *')).toBe('every 5 minutes');
    expect(formatCronHuman('*/60 * * * *')).toBe('every 60 minutes');
  });

  test('given weekly on specific day, should format with day name', () => {
    expect(formatCronHuman('0 9 * * 1')).toBe('Mon at 9:00');
  });

  test('given complex expression, should return raw cron', () => {
    expect(formatCronHuman('0 9 1,15 * *')).toBe('0 9 1,15 * *');
  });
});
