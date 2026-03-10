import type { PaneInfo } from './tmux.js';

export interface ProcessManager {
  checkAvailable(): Promise<void>;
  sessionExists(name: string): Promise<boolean>;
  ensureSession(name: string): Promise<void>;
  createWindow(session: string, name: string, cwd: string): Promise<string>;
  splitPane(target: string, direction: 'horizontal' | 'vertical', cwd: string): Promise<{ paneId: string; target: string }>;
  sendKeys(target: string, command: string): Promise<void>;
  sendLiteral(target: string, text: string): Promise<void>;
  sendRawKeys(target: string, keys: string): Promise<void>;
  sendCtrlC(target: string): Promise<void>;
  capturePane(target: string, lines?: number): Promise<string>;
  killPane(target: string): Promise<void>;
  killWindow(target: string): Promise<void>;
  getPaneInfo(target: string): Promise<PaneInfo | null>;
  listSessionPanes(session: string): Promise<Map<string, PaneInfo>>;
  listSessionWindows(session: string): Promise<WindowInfo[]>;
  killOrphanWindows(session: string, selfPaneId?: string | null): Promise<number>;
  selectWindow(target: string): Promise<void>;
  isInsideSession(): boolean;
  sanitizeName(name: string): string;
}

export interface WindowInfo {
  index: number;
  name: string;
}

// Re-export PaneInfo so consumers can import from here
export type { PaneInfo } from './tmux.js';
