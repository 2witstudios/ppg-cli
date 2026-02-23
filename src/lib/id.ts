import { customAlphabet } from 'nanoid';

const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

const shortId = customAlphabet(alphabet, 6);
const longId = customAlphabet(alphabet, 8);

export function worktreeId(): string {
  return `wt-${shortId()}`;
}

export function agentId(): string {
  return `ag-${longId()}`;
}
