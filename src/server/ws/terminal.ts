import { capturePane } from '../../core/tmux.js';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** A function that sends a message to a connected client. */
export type SendFn = (message: string) => void;

/** Wire format for terminal data pushed to subscribers. */
export interface TerminalData {
  type: 'terminal';
  agentId: string;
  lines: string[];
}

/** Wire format for terminal errors pushed to subscribers. */
export interface TerminalError {
  type: 'terminal:error';
  agentId: string;
  error: string;
}

/** Internal state for a single subscriber. */
interface Subscriber {
  id: number;
  send: SendFn;
}

/** Shared polling state for all subscribers watching the same agent. */
interface AgentStream {
  tmuxTarget: string;
  subscribers: Map<number, Subscriber>;
  timer: ReturnType<typeof setInterval> | null;
  /** Previous captured lines, used by the diff algorithm. */
  lastLines: string[];
}

// ---------------------------------------------------------------------------
// Diff algorithm — longest common suffix
// ---------------------------------------------------------------------------

/**
 * Given the previous set of lines and the current set, return only the new
 * lines that were appended to the terminal buffer.
 *
 * Strategy: find the longest suffix of `prev` that is also a prefix of `curr`.
 * Everything in `curr` after that shared region is new output.
 *
 * This handles the common terminal pattern where existing content scrolls up
 * and new content appears at the bottom. It degrades gracefully when content
 * is rewritten (e.g. TUI redraw) — in that case the full buffer is sent.
 */
export function diffLines(prev: string[], curr: string[]): string[] {
  if (prev.length === 0) return curr;
  if (curr.length === 0) return [];

  // Find the longest suffix of prev that matches a prefix of curr.
  // We search from the longest possible overlap downward.
  const maxOverlap = Math.min(prev.length, curr.length);

  for (let overlap = maxOverlap; overlap > 0; overlap--) {
    const prevStart = prev.length - overlap;
    let match = true;
    for (let i = 0; i < overlap; i++) {
      if (prev[prevStart + i] !== curr[i]) {
        match = false;
        break;
      }
    }
    if (match) {
      return curr.slice(overlap);
    }
  }

  // No shared suffix/prefix — full content is "new"
  return curr;
}

// ---------------------------------------------------------------------------
// TerminalStreamer — manages per-agent subscriptions and shared polling
// ---------------------------------------------------------------------------

const POLL_INTERVAL_MS = 500;

export class TerminalStreamer {
  private streams = new Map<string, AgentStream>();
  private nextSubscriberId = 1;
  private readonly pollIntervalMs: number;
  /** Injectable capture function — defaults to tmux capturePane. */
  private readonly capture: (target: string, lines?: number) => Promise<string>;

  constructor(options?: {
    pollIntervalMs?: number;
    capture?: (target: string, lines?: number) => Promise<string>;
  }) {
    this.pollIntervalMs = options?.pollIntervalMs ?? POLL_INTERVAL_MS;
    this.capture = options?.capture ?? capturePane;
  }

  /**
   * Subscribe a client to terminal output for an agent.
   * Returns an unsubscribe function.
   */
  subscribe(
    agentId: string,
    tmuxTarget: string,
    send: SendFn,
  ): () => void {
    const subId = this.nextSubscriberId++;

    let stream = this.streams.get(agentId);
    if (!stream) {
      stream = {
        tmuxTarget,
        subscribers: new Map(),
        timer: null,
        lastLines: [],
      };
      this.streams.set(agentId, stream);
    }

    stream.subscribers.set(subId, { id: subId, send });

    // Lazy init: start polling only when the first subscriber arrives
    if (stream.timer === null) {
      this.startPolling(agentId, stream);
    }

    // Return unsubscribe function
    return () => {
      this.unsubscribe(agentId, subId);
    };
  }

  /** Number of active subscribers for an agent. */
  subscriberCount(agentId: string): number {
    return this.streams.get(agentId)?.subscribers.size ?? 0;
  }

  /** Whether a polling timer is active for an agent. */
  isPolling(agentId: string): boolean {
    return this.streams.get(agentId)?.timer != null;
  }

  /** Tear down all streams and timers. */
  destroy(): void {
    for (const [agentId, stream] of this.streams) {
      if (stream.timer !== null) {
        clearInterval(stream.timer);
        stream.timer = null;
      }
      stream.subscribers.clear();
    }
    this.streams.clear();
  }

  // -----------------------------------------------------------------------
  // Private
  // -----------------------------------------------------------------------

  private unsubscribe(agentId: string, subId: number): void {
    const stream = this.streams.get(agentId);
    if (!stream) return;

    stream.subscribers.delete(subId);

    // Auto-cleanup: stop polling when no subscribers remain
    if (stream.subscribers.size === 0) {
      if (stream.timer !== null) {
        clearInterval(stream.timer);
        stream.timer = null;
      }
      this.streams.delete(agentId);
    }
  }

  private startPolling(agentId: string, stream: AgentStream): void {
    stream.timer = setInterval(() => {
      void this.poll(agentId, stream);
    }, this.pollIntervalMs);
  }

  private async poll(agentId: string, stream: AgentStream): Promise<void> {
    try {
      const raw = await this.capture(stream.tmuxTarget);
      const currentLines = raw.split('\n');

      const newLines = diffLines(stream.lastLines, currentLines);
      stream.lastLines = currentLines;

      if (newLines.length === 0) return;

      const message = JSON.stringify({
        type: 'terminal',
        agentId,
        lines: newLines,
      } satisfies TerminalData);

      for (const sub of stream.subscribers.values()) {
        try {
          sub.send(message);
        } catch {
          // Dead client — remove on next tick
          stream.subscribers.delete(sub.id);
        }
      }
    } catch {
      // Pane gone / tmux error — notify subscribers and clean up
      const errorMsg = JSON.stringify({
        type: 'terminal:error',
        agentId,
        error: 'Pane no longer available',
      } satisfies TerminalError);

      for (const sub of stream.subscribers.values()) {
        try {
          sub.send(errorMsg);
        } catch {
          // ignore
        }
      }

      // Stop polling — pane is dead
      if (stream.timer !== null) {
        clearInterval(stream.timer);
        stream.timer = null;
      }
      stream.subscribers.clear();
      this.streams.delete(agentId);
    }
  }
}
