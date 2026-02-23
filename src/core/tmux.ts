import { execa, ExecaError } from 'execa';
import { TmuxNotFoundError } from '../lib/errors.js';

export async function checkTmux(): Promise<void> {
  try {
    await execa('tmux', ['-V']);
  } catch {
    throw new TmuxNotFoundError();
  }
}

export async function sessionExists(name: string): Promise<boolean> {
  try {
    await execa('tmux', ['has-session', '-t', name]);
    return true;
  } catch {
    return false;
  }
}

export async function ensureSession(name: string): Promise<void> {
  if (!(await sessionExists(name))) {
    await execa('tmux', ['new-session', '-d', '-s', name, '-x', '220', '-y', '50']);
    await execa('tmux', ['set-option', '-t', name, 'mouse', 'on']);
    await execa('tmux', ['set-option', '-t', name, 'history-limit', '50000']);
  }
}

export async function createWindow(
  session: string,
  name: string,
  cwd: string,
): Promise<string> {
  const result = await execa('tmux', [
    'new-window',
    '-t', session,
    '-n', name,
    '-c', cwd,
    '-P', '-F', '#{window_index}',
  ]);
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
    '-P', '-F', '#{pane_id}',
  ]);
  const paneId = result.stdout.trim();
  return { paneId, target: paneId };
}

export async function sendKeys(target: string, command: string): Promise<void> {
  // Send command text with trailing newline in a single call
  await execa('tmux', ['send-keys', '-t', target, '-l', command + '\n']);
}

export async function sendLiteral(target: string, text: string): Promise<void> {
  await execa('tmux', ['send-keys', '-t', target, '-l', text]);
}

export async function sendRawKeys(target: string, keys: string): Promise<void> {
  await execa('tmux', ['send-keys', '-t', target, keys]);
}

export async function capturePane(target: string, lines?: number): Promise<string> {
  const args = ['capture-pane', '-t', target, '-p'];
  if (lines) {
    args.push('-S', `-${lines}`);
  }
  const result = await execa('tmux', args);
  return result.stdout;
}

export async function killPane(target: string): Promise<void> {
  try {
    await execa('tmux', ['kill-pane', '-t', target]);
  } catch {
    // Pane may already be dead
  }
}

export async function killWindow(target: string): Promise<void> {
  try {
    await execa('tmux', ['kill-window', '-t', target]);
  } catch {
    // Window may already be dead
  }
}

export interface PaneInfo {
  paneId: string;
  panePid: string;
  currentCommand: string;
  isDead: boolean;
  deadStatus?: number;
}

export async function listPanes(target: string): Promise<PaneInfo[]> {
  try {
    const result = await execa('tmux', [
      'list-panes',
      '-t', target,
      '-F', '#{pane_id}|#{pane_pid}|#{pane_current_command}|#{pane_dead}|#{pane_dead_status}',
    ]);
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
    ]);
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
      '-t', session,
      '-F', '#{session_name}:#{window_index}.#{pane_index}|#{pane_id}|#{pane_pid}|#{pane_current_command}|#{pane_dead}|#{pane_dead_status}',
    ]);
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

export async function selectPane(target: string): Promise<void> {
  await execa('tmux', ['select-pane', '-t', target]);
}

export async function selectWindow(target: string): Promise<void> {
  await execa('tmux', ['select-window', '-t', target]);
}

export async function attachSession(session: string): Promise<void> {
  // This replaces the current process, so it should be used from a non-tmux terminal
  await execa('tmux', ['attach-session', '-t', session], { stdio: 'inherit' });
}

export async function isInsideTmux(): Promise<boolean> {
  return !!process.env.TMUX;
}

export async function sendCtrlC(target: string): Promise<void> {
  await execa('tmux', ['send-keys', '-t', target, 'C-c']);
}
