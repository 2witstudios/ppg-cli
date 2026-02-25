import { execa } from 'execa';
import { warn } from '../lib/output.js';
import { shellEscape } from '../lib/shell.js';

/**
 * Open a new Terminal.app window that attaches to a specific tmux session/window.
 */
export async function openTerminalWindow(
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
