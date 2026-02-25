/**
 * Normalize a user-provided name into a valid git branch name component.
 *
 * Used to sanitize `--name` values before they become part of `ppg/<name>` branches.
 */
export function normalizeName(raw: string, fallback: string): string {
  let name = raw
    .toLowerCase()
    // Control characters → removed
    .replace(/[\x00-\x1f\x7f]+/g, '')
    // Spaces and underscores → hyphens
    .replace(/[\s_]+/g, '-')
    // Git-invalid chars → hyphens
    .replace(/[~^:?*[\]\\@{}<>]+/g, '-')
    // Collapse `..` → single dot
    .replace(/\.{2,}/g, '.')
    // Collapse consecutive slashes → single slash
    .replace(/\/{2,}/g, '/')
    // Collapse consecutive hyphens → single hyphen
    .replace(/-{2,}/g, '-')
    // Strip leading/trailing hyphens, dots, and slashes
    .replace(/^[-.\/]+|[-.\/]+$/g, '');

  // Strip `.lock` suffix repeatedly (handles `test.lock.lock`)
  while (name.endsWith('.lock')) {
    name = name.slice(0, -5);
  }

  // Final cleanup: strip trailing hyphens/dots left after .lock removal
  name = name.replace(/[-.]+$/, '');

  return name || fallback;
}
