/**
 * Escape a string for safe use with tmux send-keys -l (literal mode).
 * In literal mode, most characters are safe. We only need to handle
 * edge cases like leading dashes which tmux interprets as flags.
 */
export function escapeTmuxLiteral(text: string): string {
  let result = text;
  if (result.startsWith('-')) {
    result = '\\' + result;
  }
  return result;
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
