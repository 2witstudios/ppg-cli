import { execa } from 'execa';
import { warn } from '../lib/output.js';
import { shellEscape } from '../lib/shell.js';

/**
 * Open a new terminal window that attaches to a specific tmux session/window.
 * Uses platform-appropriate terminal emulator:
 * - macOS: Terminal.app via osascript
 * - Windows: Windows Terminal (wt.exe)
 * - Linux: $TERMINAL or falls back to common emulators
 */
export async function openTerminalWindow(
  sessionName: string,
  windowTarget: string,
  title: string,
): Promise<void> {
  const platform = process.platform;

  if (platform === 'darwin') {
    await openTerminalMac(sessionName, windowTarget, title);
  } else if (platform === 'win32') {
    await openTerminalWindows(sessionName, windowTarget, title);
  } else {
    await openTerminalLinux(sessionName, windowTarget, title);
  }
}

/** macOS: Open Terminal.app via osascript */
async function openTerminalMac(
  sessionName: string,
  windowTarget: string,
  title: string,
): Promise<void> {
  // Source shell profiles so tmux is found on M-series Macs where
  // /opt/homebrew/bin is not in the default GUI app / Terminal.app PATH.
  // Escape values for safe interpolation inside AppleScript double-quoted strings.
  const safeSession = shellEscape(sessionName);
  const safeWindow = shellEscape(windowTarget);
  const safeTitle = shellEscape(title);
  const tmuxCmd = `if [ -x /usr/libexec/path_helper ]; then eval $(/usr/libexec/path_helper -s); fi; [ -f ~/.zprofile ] && source ~/.zprofile; [ -f ~/.zshrc ] && source ~/.zshrc; tmux attach-session -t ${safeSession} \\\\; select-window -t ${safeWindow}`;

  const script = `
tell application "Terminal"
  activate
  set newTab to do script "${tmuxCmd}"
  set custom title of newTab to "${safeTitle}"
end tell
`;

  try {
    await execa('osascript', ['-e', script]);
  } catch (err) {
    warn(`Could not open Terminal window for "${title}": ${err instanceof Error ? err.message : err}`);
  }
}

/** Windows: Open Windows Terminal (wt.exe) */
async function openTerminalWindows(
  sessionName: string,
  windowTarget: string,
  title: string,
): Promise<void> {
  try {
    await execa('wt.exe', [
      'new-tab',
      '--title', title,
      'tmux', 'attach-session', '-t', sessionName, ';', 'select-window', '-t', windowTarget,
    ]);
  } catch (err) {
    warn(`Could not open Windows Terminal for "${title}": ${err instanceof Error ? err.message : err}`);
  }
}

/** Linux: Use $TERMINAL env var or fall back to common emulators */
async function openTerminalLinux(
  sessionName: string,
  windowTarget: string,
  title: string,
): Promise<void> {
  const tmuxCmd = `tmux attach-session -t ${shellEscape(sessionName)} \\; select-window -t ${shellEscape(windowTarget)}`;

  // Try $TERMINAL env var first
  const terminalEnv = process.env.TERMINAL;
  if (terminalEnv) {
    try {
      await execa(terminalEnv, ['-e', 'sh', '-c', tmuxCmd]);
      return;
    } catch {
      // Fall through to common emulators
    }
  }

  // Try common terminal emulators in order
  const emulators = [
    { cmd: 'gnome-terminal', args: ['--title', title, '--', 'sh', '-c', tmuxCmd] },
    { cmd: 'konsole', args: ['--title', title, '-e', 'sh', '-c', tmuxCmd] },
    { cmd: 'xterm', args: ['-title', title, '-e', 'sh', '-c', tmuxCmd] },
  ];

  for (const { cmd, args } of emulators) {
    try {
      await execa(cmd, args);
      return;
    } catch {
      continue;
    }
  }

  warn(`Could not open terminal window for "${title}": no supported terminal emulator found. Set $TERMINAL env var.`);
}
