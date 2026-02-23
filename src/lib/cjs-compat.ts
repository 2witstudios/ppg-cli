/**
 * Dynamic import wrappers for CJS packages that may not have proper ESM exports.
 * Uses `mod.default ?? mod` pattern to handle both CJS and ESM default exports.
 */

let _lockfile: typeof import('proper-lockfile') | undefined;
let _writeFileAtomic: typeof import('write-file-atomic').default | undefined;

export async function getLockfile() {
  if (!_lockfile) {
    const mod = await import('proper-lockfile');
    _lockfile = (mod.default ?? mod) as typeof import('proper-lockfile');
  }
  return _lockfile;
}

export async function getWriteFileAtomic() {
  if (!_writeFileAtomic) {
    const mod = await import('write-file-atomic');
    _writeFileAtomic = (mod.default ?? mod) as typeof import('write-file-atomic').default;
  }
  return _writeFileAtomic;
}
