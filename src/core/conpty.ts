/**
 * ConPTY-based process manager backend.
 *
 * EXPERIMENTAL / WIP — This backend uses node-pty (which wraps ConPTY on Windows
 * and forkpty on Unix) to manage pseudo-terminal processes without tmux.
 *
 * node-pty is an optional dependency. If it's not installed, this backend
 * cannot be instantiated — the factory in backend.ts handles the fallback.
 *
 * TODO: Production hardening
 * - Persist session registry to .ppg/pty-sessions.json on changes
 * - Restore sessions on restart
 * - Handle process crashes / unexpected exits
 * - Ring buffer sizing and memory management
 * - Window/pane layout management
 * - Signal forwarding
 */

import type { ProcessManager, WindowInfo } from './process-manager.js';
import type { PaneInfo } from './tmux.js';

// ---------------------------------------------------------------------------
// Ring buffer for capturing terminal output
// ---------------------------------------------------------------------------

class RingBuffer {
  private buffer: string[] = [];
  private readonly capacity: number;

  constructor(capacity = 5000) {
    this.capacity = capacity;
  }

  push(line: string): void {
    this.buffer.push(line);
    if (this.buffer.length > this.capacity) {
      this.buffer.shift();
    }
  }

  getLines(count?: number): string[] {
    if (!count || count >= this.buffer.length) return [...this.buffer];
    return this.buffer.slice(-count);
  }
}

// ---------------------------------------------------------------------------
// In-memory registry types
// ---------------------------------------------------------------------------

interface PtyPane {
  id: string;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  pty: any; // IPty from node-pty (typed as any to avoid hard dependency)
  output: RingBuffer;
  pid: number;
  currentCommand: string;
  isDead: boolean;
  exitCode?: number;
}

interface PtyWindow {
  index: number;
  name: string;
  panes: Map<string, PtyPane>;
}

interface PtySession {
  name: string;
  windows: Map<number, PtyWindow>;
  nextWindowIndex: number;
  nextPaneIndex: number;
}

// ---------------------------------------------------------------------------
// ConPtyBackend
// ---------------------------------------------------------------------------

let nodePty: typeof import('node-pty') | null = null;

function requireNodePty(): typeof import('node-pty') {
  if (!nodePty) {
    try {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      nodePty = require('node-pty') as typeof import('node-pty');
    } catch {
      throw new Error(
        'node-pty is required for ConPtyBackend but is not installed. ' +
        'Install it with: npm install node-pty',
      );
    }
  }
  return nodePty;
}

export class ConPtyBackend implements ProcessManager {
  private sessions = new Map<string, PtySession>();

  async checkAvailable(): Promise<void> {
    requireNodePty();
  }

  async sessionExists(name: string): Promise<boolean> {
    return this.sessions.has(name);
  }

  async ensureSession(name: string): Promise<void> {
    if (!this.sessions.has(name)) {
      this.sessions.set(name, {
        name,
        windows: new Map(),
        nextWindowIndex: 0,
        nextPaneIndex: 0,
      });
    }
  }

  async createWindow(session: string, name: string, cwd: string): Promise<string> {
    const sess = this.sessions.get(session);
    if (!sess) throw new Error(`Session "${session}" does not exist`);

    const pty = requireNodePty();
    const shell = process.platform === 'win32' ? 'cmd.exe' : (process.env.SHELL ?? 'bash');
    const windowIndex = sess.nextWindowIndex++;
    const paneId = `%${sess.nextPaneIndex++}`;

    const ptyProcess = pty.spawn(shell, [], {
      name: 'xterm-256color',
      cols: 220,
      rows: 50,
      cwd,
    });

    const output = new RingBuffer();
    let lineBuffer = '';

    ptyProcess.onData((data: string) => {
      lineBuffer += data;
      const lines = lineBuffer.split('\n');
      lineBuffer = lines.pop() ?? '';
      for (const line of lines) {
        output.push(line);
      }
    });

    const pane: PtyPane = {
      id: paneId,
      pty: ptyProcess,
      output,
      pid: ptyProcess.pid,
      currentCommand: shell,
      isDead: false,
    };

    ptyProcess.onExit(({ exitCode }: { exitCode: number }) => {
      pane.isDead = true;
      pane.exitCode = exitCode;
    });

    const win: PtyWindow = {
      index: windowIndex,
      name,
      panes: new Map([[paneId, pane]]),
    };
    sess.windows.set(windowIndex, win);

    return `${session}:${windowIndex}`;
  }

  async splitPane(target: string, _direction: 'horizontal' | 'vertical', cwd: string): Promise<{ paneId: string; target: string }> {
    const { session, windowIndex } = this.parseTarget(target);
    const sess = this.sessions.get(session);
    if (!sess) throw new Error(`Session "${session}" does not exist`);

    const win = sess.windows.get(windowIndex);
    if (!win) throw new Error(`Window ${windowIndex} does not exist in session "${session}"`);

    const pty = requireNodePty();
    const shell = process.platform === 'win32' ? 'cmd.exe' : (process.env.SHELL ?? 'bash');
    const paneId = `%${sess.nextPaneIndex++}`;
    const paneIndex = win.panes.size;

    const ptyProcess = pty.spawn(shell, [], {
      name: 'xterm-256color',
      cols: 110, // Half width for split
      rows: 50,
      cwd,
    });

    const output = new RingBuffer();
    let lineBuffer = '';

    ptyProcess.onData((data: string) => {
      lineBuffer += data;
      const lines = lineBuffer.split('\n');
      lineBuffer = lines.pop() ?? '';
      for (const line of lines) {
        output.push(line);
      }
    });

    const pane: PtyPane = {
      id: paneId,
      pty: ptyProcess,
      output,
      pid: ptyProcess.pid,
      currentCommand: shell,
      isDead: false,
    };

    ptyProcess.onExit(({ exitCode }: { exitCode: number }) => {
      pane.isDead = true;
      pane.exitCode = exitCode;
    });

    win.panes.set(paneId, pane);

    return {
      paneId,
      target: `${session}:${windowIndex}.${paneIndex}`,
    };
  }

  async sendKeys(target: string, command: string): Promise<void> {
    const pane = this.resolvePane(target);
    if (!pane || pane.isDead) return;
    pane.pty.write(command + '\r');
  }

  async sendLiteral(target: string, text: string): Promise<void> {
    const pane = this.resolvePane(target);
    if (!pane || pane.isDead) return;
    pane.pty.write(text);
  }

  async sendRawKeys(target: string, keys: string): Promise<void> {
    const pane = this.resolvePane(target);
    if (!pane || pane.isDead) return;
    // TODO: Map tmux key names (C-c, Enter, etc.) to terminal sequences
    pane.pty.write(keys);
  }

  async sendCtrlC(target: string): Promise<void> {
    const pane = this.resolvePane(target);
    if (!pane || pane.isDead) return;
    pane.pty.write('\x03');
  }

  async capturePane(target: string, lines?: number): Promise<string> {
    const pane = this.resolvePane(target);
    if (!pane) return '';
    return pane.output.getLines(lines).join('\n');
  }

  async killPane(target: string): Promise<void> {
    const pane = this.resolvePane(target);
    if (!pane) return;
    try {
      pane.pty.kill();
    } catch {
      // Already dead
    }
    pane.isDead = true;
  }

  async killWindow(target: string): Promise<void> {
    const { session, windowIndex } = this.parseTarget(target);
    const sess = this.sessions.get(session);
    if (!sess) return;

    const win = sess.windows.get(windowIndex);
    if (!win) return;

    for (const pane of win.panes.values()) {
      try {
        pane.pty.kill();
      } catch {
        // Already dead
      }
      pane.isDead = true;
    }
    sess.windows.delete(windowIndex);
  }

  async getPaneInfo(target: string): Promise<PaneInfo | null> {
    const pane = this.resolvePane(target);
    if (!pane) return null;
    return {
      paneId: pane.id,
      panePid: String(pane.pid),
      currentCommand: pane.currentCommand,
      isDead: pane.isDead,
      deadStatus: pane.exitCode,
    };
  }

  async listSessionPanes(session: string): Promise<Map<string, PaneInfo>> {
    const map = new Map<string, PaneInfo>();
    const sess = this.sessions.get(session);
    if (!sess) return map;

    for (const [winIdx, win] of sess.windows) {
      let paneIdx = 0;
      for (const [, pane] of win.panes) {
        const info: PaneInfo = {
          paneId: pane.id,
          panePid: String(pane.pid),
          currentCommand: pane.currentCommand,
          isDead: pane.isDead,
          deadStatus: pane.exitCode,
        };
        const paneTarget = `${session}:${winIdx}.${paneIdx}`;
        map.set(paneTarget, info);
        map.set(pane.id, info);
        map.set(`${session}:${winIdx}`, info);
        paneIdx++;
      }
    }
    return map;
  }

  async listSessionWindows(session: string): Promise<WindowInfo[]> {
    const sess = this.sessions.get(session);
    if (!sess) return [];
    return Array.from(sess.windows.values()).map((w) => ({
      index: w.index,
      name: w.name,
    }));
  }

  async killOrphanWindows(session: string, selfPaneId?: string | null): Promise<number> {
    const sess = this.sessions.get(session);
    if (!sess) return 0;

    let killed = 0;
    for (const [idx, win] of sess.windows) {
      if (idx === 0) continue;

      // Self-protection
      if (selfPaneId) {
        let containsSelf = false;
        for (const pane of win.panes.values()) {
          if (pane.id === selfPaneId) {
            containsSelf = true;
            break;
          }
        }
        if (containsSelf) continue;
      }

      for (const pane of win.panes.values()) {
        try {
          pane.pty.kill();
        } catch {
          // Already dead
        }
      }
      sess.windows.delete(idx);
      killed++;
    }
    return killed;
  }

  async selectWindow(_target: string): Promise<void> {
    // No-op for ConPTY — no concept of "selecting" a window in a terminal multiplexer
    // TODO: Could bring a specific window to focus in Windows Terminal
  }

  isInsideSession(): boolean {
    // ConPTY sessions are in-process, so we're never "inside" one the way tmux works
    return false;
  }

  sanitizeName(name: string): string {
    // Same rules as tmux for target format compatibility
    return name.replace(/[.:]/g, '-');
  }

  // -----------------------------------------------------------------------
  // Private helpers
  // -----------------------------------------------------------------------

  private parseTarget(target: string): { session: string; windowIndex: number; paneIndex?: number } {
    const colonIdx = target.indexOf(':');
    if (colonIdx === -1) {
      return { session: target, windowIndex: 0 };
    }
    const session = target.slice(0, colonIdx);
    const rest = target.slice(colonIdx + 1);
    const dotIdx = rest.indexOf('.');
    if (dotIdx === -1) {
      return { session, windowIndex: parseInt(rest, 10) };
    }
    return {
      session,
      windowIndex: parseInt(rest.slice(0, dotIdx), 10),
      paneIndex: parseInt(rest.slice(dotIdx + 1), 10),
    };
  }

  private resolvePane(target: string): PtyPane | null {
    const { session, windowIndex, paneIndex } = this.parseTarget(target);
    const sess = this.sessions.get(session);
    if (!sess) return null;

    const win = sess.windows.get(windowIndex);
    if (!win) return null;

    if (paneIndex !== undefined) {
      const panes = Array.from(win.panes.values());
      return panes[paneIndex] ?? null;
    }

    // Default to first pane in the window
    const firstPane = win.panes.values().next();
    return firstPane.done ? null : firstPane.value;
  }
}
