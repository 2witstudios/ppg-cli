import { execa, ExecaError } from 'execa';
import { TmuxNotFoundError } from '../lib/errors.js';
import { execaEnv } from '../lib/env.js';

export async function checkTmux(): Promise<void> {
  try {
    await execa('tmux', ['-V'], execaEnv);
  } catch {
    throw new TmuxNotFoundError();
  }
}

export async function sessionExists(name: string): Promise<boolean> {
  try {
    // Use '=' prefix for exact session name matching to avoid tmux prefix ambiguity
    await execa('tmux', ['has-session', '-t', `=${name}`], execaEnv);
    return true;
  } catch {
    return false;
  }
}

export async function ensureSession(name: string): Promise<void> {
  if (!(await sessionExists(name))) {
    await execa('tmux', ['new-session', '-d', '-s', name, '-x', '220', '-y', '50'], execaEnv);
    await execa('tmux', ['set-option', '-t', name, 'mouse', 'on'], execaEnv);
    await execa('tmux', ['set-option', '-t', name, 'history-limit', '50000'], execaEnv);
  }
}

export async function createWindow(
  session: string,
  name: string,
  cwd: string,
): Promise<string> {
  // Use '=' prefix for exact session name matching to avoid tmux prefix ambiguity
  // (e.g., 'ppg' would otherwise match both 'ppg' and 'ppg-dashboard')
  const result = await execa('tmux', [
    'new-window',
    '-t', `=${session}`,
    '-n', name,
    '-c', cwd,
    '-P', '-F', '#{window_index}',
  ], execaEnv);
  const windowIndex = result.stdout.trim();
  return `${session}:${windowIndex}`;
}

export async function splitPane(
  target: string,
  direction: 'horizontal' | 'vertical',
  cwd: string,
): Promise<{ paneId: string; target: string }> {
  const flag = direction === 'horizontal' ? '-h' : '-v';
  const result = await execa('tmux', [
    'split-window',
    flag,
    '-t', target,
    '-c', cwd,
    '-P', '-F', '#{session_name}:#{window_index}.#{pane_index}|#{pane_id}',
  ], execaEnv);
  const [canonicalTarget, paneId] = result.stdout.trim().split('|');
  return { paneId, target: canonicalTarget };
}

export async function sendKeys(target: string, command: string): Promise<void> {
  // Send text as literal characters, then Enter as a named key.
  // Using -l sends \n as LF (0x0a) which Ink-based CLIs like Claude Code
  // treat as text insertion. Sending 'Enter' without -l sends CR (0x0d),
  // which correctly triggers onSubmit in terminal apps.
  await execa('tmux', ['send-keys', '-t', target, '-l', command], execaEnv);
  await execa('tmux', ['send-keys', '-t', target, 'Enter'], execaEnv);
}

export async function sendLiteral(target: string, text: string): Promise<void> {
  await execa('tmux', ['send-keys', '-t', target, '-l', text], execaEnv);
}

export async function sendRawKeys(target: string, keys: string): Promise<void> {
  await execa('tmux', ['send-keys', '-t', target, keys], execaEnv);
}

export async function capturePane(target: string, lines?: number): Promise<string> {
  const args = ['capture-pane', '-t', target, '-p'];
  if (lines) {
    args.push('-S', `-${lines}`);
  }
  const result = await execa('tmux', args, execaEnv);
  return result.stdout;
}

export async function killPane(target: string): Promise<void> {
  try {
    await execa('tmux', ['kill-pane', '-t', target], execaEnv);
  } catch (err) {
    if (isTmuxNotFoundError(err)) return;
    throw err;
  }
}

export async function killWindow(target: string): Promise<void> {
  try {
    await execa('tmux', ['kill-window', '-t', target], execaEnv);
  } catch (err) {
    if (isTmuxNotFoundError(err)) return;
    throw err;
  }
}

/**
 * Check if a tmux error is a benign "not found" error (target already dead/gone).
 * Returns true for errors that should be silently ignored.
 */
function isTmuxNotFoundError(err: unknown): boolean {
  if (!(err instanceof ExecaError)) return false;
  const msg = (String(err.stderr ?? '')).toLowerCase();
  return msg.includes("can't find") ||
    msg.includes('not found') ||
    msg.includes('no such') ||
    msg.includes('session not found') ||
    msg.includes('window not found') ||
    msg.includes('pane not found');
}

export interface PaneInfo {
  paneId: string;
  panePid: string;
  currentCommand: string;
  isDead: boolean;
  deadStatus?: number;
}

async function listPanes(target: string): Promise<PaneInfo[]> {
  try {
    const result = await execa('tmux', [
      'list-panes',
      '-t', target,
      '-F', '#{pane_id}|#{pane_pid}|#{pane_current_command}|#{pane_dead}|#{pane_dead_status}',
    ], execaEnv);
    return result.stdout.trim().split('\n').filter(Boolean).map((line) => {
      const [paneId, panePid, currentCommand, dead, deadStatus] = line.split('|');
      return {
        paneId,
        panePid,
        currentCommand,
        isDead: dead === '1',
        deadStatus: deadStatus ? parseInt(deadStatus, 10) : undefined,
      };
    });
  } catch {
    return [];
  }
}

export async function getPaneInfo(target: string): Promise<PaneInfo | null> {
  try {
    const result = await execa('tmux', [
      'display-message',
      '-t', target,
      '-p',
      '#{pane_id}|#{pane_pid}|#{pane_current_command}|#{pane_dead}|#{pane_dead_status}',
    ], execaEnv);
    const [paneId, panePid, currentCommand, dead, deadStatus] = result.stdout.trim().split('|');
    return {
      paneId,
      panePid,
      currentCommand,
      isDead: dead === '1',
      deadStatus: deadStatus ? parseInt(deadStatus, 10) : undefined,
    };
  } catch {
    return null;
  }
}

/**
 * List all panes in a session with a single tmux call.
 * Returns a map keyed by pane target (session:window.pane format).
 */
export async function listSessionPanes(session: string): Promise<Map<string, PaneInfo>> {
  const map = new Map<string, PaneInfo>();
  try {
    const result = await execa('tmux', [
      'list-panes',
      '-s',
      '-t', `=${session}`,
      '-F', '#{session_name}:#{window_index}.#{pane_index}|#{pane_id}|#{pane_pid}|#{pane_current_command}|#{pane_dead}|#{pane_dead_status}',
    ], execaEnv);
    for (const line of result.stdout.trim().split('\n').filter(Boolean)) {
      const [target, paneId, panePid, currentCommand, dead, deadStatus] = line.split('|');
      const info: PaneInfo = {
        paneId,
        panePid,
        currentCommand,
        isDead: dead === '1',
        deadStatus: deadStatus ? parseInt(deadStatus, 10) : undefined,
      };
      // Index by multiple target formats for flexible lookup
      map.set(target, info);                          // session:window.pane
      map.set(paneId, info);                          // %paneId
      const dotIdx = target.lastIndexOf('.');
      if (dotIdx !== -1) {
        map.set(target.slice(0, dotIdx), info);       // session:window
      }
    }
  } catch {
    // Session may not exist
  }
  return map;
}

export interface WindowInfo {
  index: number;
  name: string;
}

/**
 * List all windows in a tmux session.
 * Returns window index and name for each window.
 */
export async function listSessionWindows(session: string): Promise<WindowInfo[]> {
  try {
    const result = await execa('tmux', [
      'list-windows',
      '-t', `=${session}`,
      '-F', '#{window_index} #{window_name}',
    ], execaEnv);
    return result.stdout.trim().split('\n').filter(Boolean).map((line) => {
      const spaceIdx = line.indexOf(' ');
      return {
        index: parseInt(line.slice(0, spaceIdx), 10),
        name: line.slice(spaceIdx + 1),
      };
    });
  } catch {
    return [];
  }
}

/**
 * Kill all non-base windows in a session (orphan cleanup).
 * Window 0 is preserved as the base shell window.
 * Returns the number of windows killed.
 */
export async function killOrphanWindows(session: string): Promise<number> {
  const windows = await listSessionWindows(session);
  let killed = 0;
  for (const win of windows) {
    if (win.index === 0) continue;
    try {
      await killWindow(`${session}:${win.index}`);
      killed++;
    } catch {
      // Already gone — fine
    }
  }
  return killed;
}

export async function selectWindow(target: string): Promise<void> {
  await execa('tmux', ['select-window', '-t', target], execaEnv);
}

export async function isInsideTmux(): Promise<boolean> {
  return !!process.env.TMUX;
}

export async function sendCtrlC(target: string): Promise<void> {
  await execa('tmux', ['send-keys', '-t', target, 'C-c'], execaEnv);
}
