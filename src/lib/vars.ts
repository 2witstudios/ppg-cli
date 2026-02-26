import { PpgError } from './errors.js';

/**
 * Parse CLI --var KEY=value arguments into a record.
 * Throws INVALID_ARGS if any entry is missing '=' or has an empty key.
 */
export function parseVars(vars: string[]): Record<string, string> {
  const result: Record<string, string> = {};
  for (const v of vars) {
    const eqIdx = v.indexOf('=');
    if (eqIdx < 1) {
      throw new PpgError(`Invalid --var format: "${v}" — expected KEY=value`, 'INVALID_ARGS');
    }
    result[v.slice(0, eqIdx)] = v.slice(eqIdx + 1);
  }
  return result;
}
