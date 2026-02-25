import { execa } from 'execa';
import { warn } from '../lib/output.js';

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
  const tmuxCmd = `if [ -x /usr/libexec/path_helper ]; then eval $(/usr/libexec/path_helper -s); fi; [ -f ~/.zprofile ] && source ~/.zprofile; [ -f ~/.zshrc ] && source ~/.zshrc; tmux attach-session -t ${sessionName} \\\\; select-window -t ${windowTarget}`;

  const script = `
tell application "Terminal"
  activate
  set newTab to do script "${tmuxCmd}"
  set custom title of newTab to "${title}"
end tell
`;

  try {
    await execa('osascript', ['-e', script]);
  } catch (err) {
    warn(`Could not open Terminal window for "${title}": ${err instanceof Error ? err.message : err}`);
  }
}
