import type { ProcessManager } from './process-manager.js';
import { TmuxBackend } from './tmux.js';

let _backend: ProcessManager | null = null;

export function createBackend(): ProcessManager {
  if (process.platform === 'win32') {
    // Dynamic import to avoid requiring node-pty on non-Windows
    // For now, default to TmuxBackend even on Windows if tmux is available (WSL scenario)
    try {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const { ConPtyBackend } = require('./conpty.js') as typeof import('./conpty.js');
      return new ConPtyBackend();
    } catch {
      // node-pty not installed, fall back to tmux
      return new TmuxBackend();
    }
  }
  return new TmuxBackend();
}

export function getBackend(): ProcessManager {
  if (!_backend) _backend = createBackend();
  return _backend;
}

/** For testing — allow injecting a mock backend */
export function setBackend(backend: ProcessManager): void {
  _backend = backend;
}

export function resetBackend(): void {
  _backend = null;
}
