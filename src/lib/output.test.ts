import { describe, test, expect } from 'vitest';
import { formatTable, type Column } from './output.js';

describe('formatTable', () => {
  const columns: Column[] = [
    { header: 'ID', key: 'id' },
    { header: 'Name', key: 'name' },
    { header: 'Status', key: 'status' },
  ];

  test('given empty rows, should return "No results."', () => {
    expect(formatTable([], columns)).toBe('No results.');
  });

  test('given basic rows, should format header, separator, and body', () => {
    const rows = [
      { id: 'wt-abc', name: 'auth', status: 'active' },
      { id: 'wt-def', name: 'billing', status: 'merged' },
    ];
    const result = formatTable(rows, columns);
    const lines = result.split('\n');

    // Header, separator, 2 data rows
    expect(lines).toHaveLength(4);

    // Strip ANSI to verify content
    const strip = (s: string) => s.replace(/\x1b\[[0-9;]*m/g, '');

    const header = strip(lines[0]);
    expect(header).toContain('ID');
    expect(header).toContain('Name');
    expect(header).toContain('Status');

    // Separator line uses ─
    const sep = strip(lines[1]);
    expect(sep).toMatch(/─+/);

    // Data rows
    const row1 = strip(lines[2]);
    expect(row1).toContain('wt-abc');
    expect(row1).toContain('auth');
    expect(row1).toContain('active');

    const row2 = strip(lines[3]);
    expect(row2).toContain('wt-def');
    expect(row2).toContain('billing');
    expect(row2).toContain('merged');
  });

  test('given ANSI-colored values, should calculate width from stripped text', () => {
    const coloredColumns: Column[] = [
      { header: 'Status', key: 'status', format: (v) => `\x1b[32m${v}\x1b[0m` },
    ];
    const rows = [{ status: 'running' }];
    const result = formatTable(rows, coloredColumns);
    const lines = result.split('\n');

    // Width should be based on "running" (7 chars) or "Status" (6 chars), so 7
    const strip = (s: string) => s.replace(/\x1b\[[0-9;]*m/g, '');
    const headerStripped = strip(lines[0]);
    // Header "Status" padded to at least 7 chars (length of "running")
    expect(headerStripped.length).toBeGreaterThanOrEqual(7);
  });

  test('given explicit column width, should use it', () => {
    const fixedColumns: Column[] = [
      { header: 'ID', key: 'id', width: 20 },
    ];
    const rows = [{ id: 'x' }];
    const result = formatTable(rows, fixedColumns);
    const strip = (s: string) => s.replace(/\x1b\[[0-9;]*m/g, '');
    const dataRow = strip(result.split('\n')[2]);
    // "x" padded to 20 chars
    expect(dataRow.length).toBeGreaterThanOrEqual(20);
  });

  test('given format function, should use it for display', () => {
    const fmtColumns: Column[] = [
      { header: 'Count', key: 'count', format: (v) => `#${v}` },
    ];
    const rows = [{ count: 42 }];
    const result = formatTable(rows, fmtColumns);
    const strip = (s: string) => s.replace(/\x1b\[[0-9;]*m/g, '');
    expect(strip(result)).toContain('#42');
  });
});
