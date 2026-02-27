import { describe, test, expect } from 'vitest';
import { sanitizeTmuxName } from './tmux.js';

describe('sanitizeTmuxName', () => {
  test('given name with dots, should replace with hyphens', () => {
    expect(sanitizeTmuxName('ppg-reporttoxicity.com')).toBe('ppg-reporttoxicity-com');
  });

  test('given name with colons, should replace with hyphens', () => {
    expect(sanitizeTmuxName('ppg-my:project')).toBe('ppg-my-project');
  });

  test('given name with multiple dots and colons, should replace all', () => {
    expect(sanitizeTmuxName('ppg-my.site.co:8080')).toBe('ppg-my-site-co-8080');
  });

  test('given clean name, should return unchanged', () => {
    expect(sanitizeTmuxName('ppg-my-project')).toBe('ppg-my-project');
  });
});
