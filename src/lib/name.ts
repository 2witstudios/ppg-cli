/**
 * Normalize a user-provided name into a valid git branch name component.
 *
 * Used to sanitize `--name` values before they become part of `pogu/<name>` branches.
 */
export function normalizeName(raw: string, fallback: string): string {
  const name = raw
    .toLowerCase()
    // Control characters → removed
    .replace(/[\x00-\x1f\x7f]+/g, '')
    // Spaces and underscores → hyphens
    .replace(/[\s_]+/g, '-')
    // Git-invalid chars → hyphens
    .replace(/[~^:?*[\]\\@{}<>]+/g, '-')
    // Collapse `..` → single dot
    .replace(/\.{2,}/g, '.')
    // Collapse consecutive hyphens → single hyphen
    .replace(/-{2,}/g, '-')
    // Split on slash, normalize each segment, rejoin
    .split('/')
    .map(normalizeSegment)
    .filter(Boolean)
    .join('/');

  return name || fallback;
}

function normalizeSegment(segment: string): string {
  let s = segment;

  // Strip `.lock` suffix repeatedly (before trimming dots, so `.lock` → empty)
  while (s.endsWith('.lock')) {
    s = s.slice(0, -5);
  }

  // Strip leading/trailing hyphens and dots
  s = s.replace(/^[-.]+|[-.]+$/g, '');

  return s;
}
