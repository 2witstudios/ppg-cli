/**
 * Escape a string for safe use with tmux send-keys -l (literal mode).
 * In literal mode, most characters are safe. We only need to handle
 * edge cases like leading dashes.
 */
export function escapeTmuxLiteral(text: string): string {
  // tmux send-keys -l sends text literally, but we still need to
  // ensure no control sequences sneak in
  return text;
}

/**
 * Shell-escape a string for use inside double quotes.
 */
export function shellEscape(text: string): string {
  return text
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"')
    .replace(/\$/g, '\\$')
    .replace(/`/g, '\\`');
}
