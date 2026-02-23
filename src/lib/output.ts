import type { AgentStatus, WorktreeStatus } from '../types/manifest.js';

const RESET = '\x1b[0m';
const BOLD = '\x1b[1m';
const DIM = '\x1b[2m';
const RED = '\x1b[31m';
const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const BLUE = '\x1b[34m';
const MAGENTA = '\x1b[35m';
const CYAN = '\x1b[36m';
const GRAY = '\x1b[90m';

const STATUS_COLORS: Record<AgentStatus | WorktreeStatus, string> = {
  spawning: YELLOW,
  running: GREEN,
  waiting: CYAN,
  completed: BLUE,
  failed: RED,
  killed: MAGENTA,
  lost: RED + BOLD,
  active: GREEN,
  merging: YELLOW,
  merged: BLUE,
  cleaned: GRAY,
};

export function formatStatus(status: AgentStatus | WorktreeStatus): string {
  const color = STATUS_COLORS[status] ?? RESET;
  return `${color}${status}${RESET}`;
}

export function output(data: unknown, json: boolean): void {
  if (json) {
    console.log(JSON.stringify(data, null, 2));
  } else if (typeof data === 'string') {
    console.log(data);
  } else {
    console.log(data);
  }
}

export function outputError(error: unknown, json: boolean): void {
  if (json) {
    const message = error instanceof Error ? error.message : String(error);
    const code = error instanceof Error && 'code' in error
      ? (error as { code: string }).code
      : 'UNKNOWN';
    console.error(JSON.stringify({ error: message, code }));
  } else {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`${RED}Error:${RESET} ${message}`);
  }
}

export interface Column {
  header: string;
  key: string;
  width?: number;
  format?: (value: unknown) => string;
}

export function formatTable(rows: Record<string, unknown>[], columns: Column[]): string {
  if (rows.length === 0) return 'No results.';

  // Calculate column widths
  const widths = columns.map((col) => {
    const headerLen = col.header.length;
    const maxDataLen = rows.reduce((max, row) => {
      const val = col.format ? col.format(row[col.key]) : String(row[col.key] ?? '');
      // Strip ANSI for width calculation
      const stripped = val.replace(/\x1b\[[0-9;]*m/g, '');
      return Math.max(max, stripped.length);
    }, 0);
    return col.width ?? Math.max(headerLen, maxDataLen);
  });

  // Header
  const header = columns
    .map((col, i) => `${BOLD}${col.header.padEnd(widths[i])}${RESET}`)
    .join('  ');

  const separator = widths.map((w) => DIM + '─'.repeat(w) + RESET).join('  ');

  // Rows
  const body = rows.map((row) =>
    columns
      .map((col, i) => {
        const val = col.format ? col.format(row[col.key]) : String(row[col.key] ?? '');
        const stripped = val.replace(/\x1b\[[0-9;]*m/g, '');
        const padding = Math.max(0, widths[i] - stripped.length);
        return val + ' '.repeat(padding);
      })
      .join('  '),
  ).join('\n');

  return `${header}\n${separator}\n${body}`;
}

export function info(message: string): void {
  console.log(`${CYAN}▸${RESET} ${message}`);
}

export function success(message: string): void {
  console.log(`${GREEN}✓${RESET} ${message}`);
}

export function warn(message: string): void {
  console.log(`${YELLOW}⚠${RESET} ${message}`);
}
