import type { AgentStatus, Manifest, WorktreeStatus } from '../../types/manifest.js';

// --- Inbound Commands (client → server) ---

export interface PingCommand {
  type: 'ping';
}

export interface TerminalSubscribeCommand {
  type: 'terminal:subscribe';
  agentId: string;
}

export interface TerminalUnsubscribeCommand {
  type: 'terminal:unsubscribe';
  agentId: string;
}

export interface TerminalInputCommand {
  type: 'terminal:input';
  agentId: string;
  data: string;
}

export type ClientCommand =
  | PingCommand
  | TerminalSubscribeCommand
  | TerminalUnsubscribeCommand
  | TerminalInputCommand;

// --- Outbound Events (server → client) ---

export interface PongEvent {
  type: 'pong';
}

export interface ManifestUpdatedEvent {
  type: 'manifest:updated';
  manifest: Manifest;
}

export interface AgentStatusEvent {
  type: 'agent:status';
  worktreeId: string;
  agentId: string;
  status: AgentStatus;
  worktreeStatus: WorktreeStatus;
}

export interface TerminalOutputEvent {
  type: 'terminal:output';
  agentId: string;
  data: string;
}

export interface ErrorEvent {
  type: 'error';
  code: string;
  message: string;
}

export type ServerEvent =
  | PongEvent
  | ManifestUpdatedEvent
  | AgentStatusEvent
  | TerminalOutputEvent
  | ErrorEvent;

// --- Parsing ---

const VALID_COMMAND_TYPES = new Set([
  'ping',
  'terminal:subscribe',
  'terminal:unsubscribe',
  'terminal:input',
]);

export function parseCommand(raw: string): ClientCommand | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }

  if (typeof parsed !== 'object' || parsed === null) return null;

  const obj = parsed as Record<string, unknown>;
  if (typeof obj.type !== 'string' || !VALID_COMMAND_TYPES.has(obj.type)) return null;

  if (obj.type === 'ping') {
    return { type: 'ping' };
  }

  if (obj.type === 'terminal:subscribe' || obj.type === 'terminal:unsubscribe') {
    if (typeof obj.agentId !== 'string') return null;
    return { type: obj.type, agentId: obj.agentId };
  }

  if (obj.type === 'terminal:input') {
    if (typeof obj.agentId !== 'string' || typeof obj.data !== 'string') return null;
    return { type: 'terminal:input', agentId: obj.agentId, data: obj.data };
  }

  return null;
}

export function serializeEvent(event: ServerEvent): string {
  return JSON.stringify(event);
}
