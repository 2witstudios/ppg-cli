import { describe, test, expect, vi, beforeEach, afterEach } from 'vitest';
import { diffLines, TerminalStreamer } from './terminal.js';
import type { TerminalData, TerminalError } from './terminal.js';

// ---------------------------------------------------------------------------
// diffLines — longest common suffix algorithm
// ---------------------------------------------------------------------------

describe('diffLines', () => {
  test('given empty prev, should return all of curr', () => {
    const result = diffLines([], ['line1', 'line2']);
    expect(result).toEqual(['line1', 'line2']);
  });

  test('given empty curr, should return empty', () => {
    const result = diffLines(['line1', 'line2'], []);
    expect(result).toEqual([]);
  });

  test('given identical buffers, should return empty', () => {
    const lines = ['a', 'b', 'c'];
    const result = diffLines(lines, [...lines]);
    expect(result).toEqual([]);
  });

  test('given appended lines, should return only new lines', () => {
    const prev = ['line1', 'line2'];
    const curr = ['line1', 'line2', 'line3', 'line4'];
    const result = diffLines(prev, curr);
    expect(result).toEqual(['line3', 'line4']);
  });

  test('given scrolled buffer with new lines, should return new lines', () => {
    // Terminal scrolled: line1 is gone, lines 2-3 remain, line4 is new
    const prev = ['line1', 'line2', 'line3'];
    const curr = ['line2', 'line3', 'line4'];
    const result = diffLines(prev, curr);
    expect(result).toEqual(['line4']);
  });

  test('given completely different content, should return all of curr', () => {
    const prev = ['aaa', 'bbb'];
    const curr = ['xxx', 'yyy'];
    const result = diffLines(prev, curr);
    expect(result).toEqual(['xxx', 'yyy']);
  });

  test('given partial overlap in scrolled buffer, should detect suffix match', () => {
    const prev = ['a', 'b', 'c', 'd'];
    const curr = ['c', 'd', 'e', 'f'];
    const result = diffLines(prev, curr);
    expect(result).toEqual(['e', 'f']);
  });

  test('given single line overlap, should return new lines after overlap', () => {
    const prev = ['x', 'y', 'z'];
    const curr = ['z', 'new1', 'new2'];
    const result = diffLines(prev, curr);
    expect(result).toEqual(['new1', 'new2']);
  });

  test('given prev longer than curr with overlap, should return new lines', () => {
    const prev = ['a', 'b', 'c', 'd', 'e'];
    const curr = ['d', 'e', 'f'];
    const result = diffLines(prev, curr);
    expect(result).toEqual(['f']);
  });

  test('given trailing empty lines from tmux, should handle correctly', () => {
    // capturePane often returns "line1\nline2\n" → split gives trailing ''
    const prev = ['line1', 'line2', ''];
    const curr = ['line1', 'line2', '', 'line3', ''];
    const result = diffLines(prev, curr);
    expect(result).toEqual(['line3', '']);
  });
});

// ---------------------------------------------------------------------------
// TerminalStreamer
// ---------------------------------------------------------------------------

describe('TerminalStreamer', () => {
  let streamer: TerminalStreamer;
  let mockCapture: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    vi.useFakeTimers();
    mockCapture = vi.fn<(target: string, lines?: number) => Promise<string>>();
    streamer = new TerminalStreamer({
      pollIntervalMs: 500,
      capture: mockCapture,
    });
  });

  afterEach(() => {
    streamer.destroy();
    vi.useRealTimers();
  });

  // -- Subscription lifecycle -----------------------------------------------

  describe('subscription lifecycle', () => {
    test('given first subscriber, should start polling', () => {
      mockCapture.mockResolvedValue('hello');
      const send = vi.fn();

      streamer.subscribe('ag-001', 'ppg:1.0', send);

      expect(streamer.subscriberCount('ag-001')).toBe(1);
      expect(streamer.isPolling('ag-001')).toBe(true);
    });

    test('given second subscriber, should share timer', () => {
      mockCapture.mockResolvedValue('hello');
      const send1 = vi.fn();
      const send2 = vi.fn();

      streamer.subscribe('ag-001', 'ppg:1.0', send1);
      streamer.subscribe('ag-001', 'ppg:1.0', send2);

      expect(streamer.subscriberCount('ag-001')).toBe(2);
      expect(streamer.isPolling('ag-001')).toBe(true);
    });

    test('given unsubscribe of one, should keep timer for remaining', () => {
      mockCapture.mockResolvedValue('hello');
      const send1 = vi.fn();
      const send2 = vi.fn();

      const unsub1 = streamer.subscribe('ag-001', 'ppg:1.0', send1);
      streamer.subscribe('ag-001', 'ppg:1.0', send2);

      unsub1();

      expect(streamer.subscriberCount('ag-001')).toBe(1);
      expect(streamer.isPolling('ag-001')).toBe(true);
    });

    test('given all unsubscribed, should stop polling and cleanup', () => {
      mockCapture.mockResolvedValue('hello');
      const send = vi.fn();

      const unsub = streamer.subscribe('ag-001', 'ppg:1.0', send);
      unsub();

      expect(streamer.subscriberCount('ag-001')).toBe(0);
      expect(streamer.isPolling('ag-001')).toBe(false);
    });

    test('given double unsubscribe, should be idempotent', () => {
      mockCapture.mockResolvedValue('hello');
      const send = vi.fn();

      const unsub = streamer.subscribe('ag-001', 'ppg:1.0', send);
      unsub();
      unsub(); // second call should not throw

      expect(streamer.subscriberCount('ag-001')).toBe(0);
      expect(streamer.isPolling('ag-001')).toBe(false);
    });

    test('given multiple agents, should track independently', () => {
      mockCapture.mockResolvedValue('hello');
      const send1 = vi.fn();
      const send2 = vi.fn();

      streamer.subscribe('ag-001', 'ppg:1.0', send1);
      streamer.subscribe('ag-002', 'ppg:1.1', send2);

      expect(streamer.subscriberCount('ag-001')).toBe(1);
      expect(streamer.subscriberCount('ag-002')).toBe(1);
      expect(streamer.isPolling('ag-001')).toBe(true);
      expect(streamer.isPolling('ag-002')).toBe(true);
    });
  });

  // -- Polling & diff -------------------------------------------------------

  describe('polling and diff', () => {
    test('given initial content, should send all lines on first poll', async () => {
      mockCapture.mockResolvedValue('line1\nline2\nline3');
      const send = vi.fn();

      streamer.subscribe('ag-001', 'ppg:1.0', send);

      await vi.advanceTimersByTimeAsync(500);

      expect(mockCapture).toHaveBeenCalledWith('ppg:1.0');
      expect(send).toHaveBeenCalledTimes(1);

      const msg: TerminalData = JSON.parse(send.mock.calls[0][0]);
      expect(msg.type).toBe('terminal');
      expect(msg.agentId).toBe('ag-001');
      expect(msg.lines).toEqual(['line1', 'line2', 'line3']);
    });

    test('given unchanged content, should not send', async () => {
      mockCapture.mockResolvedValue('line1\nline2');
      const send = vi.fn();

      streamer.subscribe('ag-001', 'ppg:1.0', send);

      await vi.advanceTimersByTimeAsync(500);
      expect(send).toHaveBeenCalledTimes(1);

      // Same content on next poll
      await vi.advanceTimersByTimeAsync(500);
      expect(send).toHaveBeenCalledTimes(1); // No new call
    });

    test('given new lines appended, should send only diff', async () => {
      mockCapture.mockResolvedValueOnce('line1\nline2');
      const send = vi.fn();

      streamer.subscribe('ag-001', 'ppg:1.0', send);
      await vi.advanceTimersByTimeAsync(500);

      // New lines appended
      mockCapture.mockResolvedValueOnce('line1\nline2\nline3\nline4');
      await vi.advanceTimersByTimeAsync(500);

      expect(send).toHaveBeenCalledTimes(2);
      const msg: TerminalData = JSON.parse(send.mock.calls[1][0]);
      expect(msg.lines).toEqual(['line3', 'line4']);
    });

    test('given content broadcast to multiple subscribers, should send to all', async () => {
      mockCapture.mockResolvedValue('hello');
      const send1 = vi.fn();
      const send2 = vi.fn();

      streamer.subscribe('ag-001', 'ppg:1.0', send1);
      streamer.subscribe('ag-001', 'ppg:1.0', send2);

      await vi.advanceTimersByTimeAsync(500);

      expect(send1).toHaveBeenCalledTimes(1);
      expect(send2).toHaveBeenCalledTimes(1);
      expect(send1.mock.calls[0][0]).toBe(send2.mock.calls[0][0]);
    });

    test('given 500ms interval, should not poll before interval', async () => {
      mockCapture.mockResolvedValue('hello');
      const send = vi.fn();

      streamer.subscribe('ag-001', 'ppg:1.0', send);

      await vi.advanceTimersByTimeAsync(200);
      expect(mockCapture).not.toHaveBeenCalled();

      await vi.advanceTimersByTimeAsync(300);
      expect(mockCapture).toHaveBeenCalledTimes(1);
    });
  });

  // -- Error handling -------------------------------------------------------

  describe('error handling', () => {
    test('given pane capture fails, should send error and cleanup', async () => {
      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
      mockCapture.mockRejectedValue(new Error('pane not found'));
      const send = vi.fn();

      streamer.subscribe('ag-001', 'ppg:1.0', send);

      await vi.advanceTimersByTimeAsync(500);

      expect(send).toHaveBeenCalledTimes(1);
      const msg: TerminalError = JSON.parse(send.mock.calls[0][0]);
      expect(msg.type).toBe('terminal:error');
      expect(msg.agentId).toBe('ag-001');
      expect(msg.error).toBe('Pane no longer available');

      // Original error should be logged
      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringContaining('pane not found'),
      );

      // Stream should be cleaned up
      expect(streamer.subscriberCount('ag-001')).toBe(0);
      expect(streamer.isPolling('ag-001')).toBe(false);
      consoleSpy.mockRestore();
    });

    test('given dead subscriber send throws, should remove subscriber', async () => {
      mockCapture.mockResolvedValue('line1');
      const goodSend = vi.fn();
      const badSend = vi.fn().mockImplementation(() => {
        throw new Error('connection closed');
      });

      streamer.subscribe('ag-001', 'ppg:1.0', badSend);
      streamer.subscribe('ag-001', 'ppg:1.0', goodSend);

      await vi.advanceTimersByTimeAsync(500);

      // Good subscriber got the message
      expect(goodSend).toHaveBeenCalledTimes(1);
      // Bad subscriber was removed
      expect(streamer.subscriberCount('ag-001')).toBe(1);
    });
  });

  // -- Shared timer ---------------------------------------------------------

  describe('shared timer', () => {
    test('given shared timer, should only call capture once per interval', async () => {
      mockCapture.mockResolvedValue('data');
      const send1 = vi.fn();
      const send2 = vi.fn();
      const send3 = vi.fn();

      streamer.subscribe('ag-001', 'ppg:1.0', send1);
      streamer.subscribe('ag-001', 'ppg:1.0', send2);
      streamer.subscribe('ag-001', 'ppg:1.0', send3);

      await vi.advanceTimersByTimeAsync(500);

      // Only one capture call despite three subscribers
      expect(mockCapture).toHaveBeenCalledTimes(1);
    });
  });

  // -- destroy --------------------------------------------------------------

  describe('destroy', () => {
    test('given active streams, should clean up everything', async () => {
      mockCapture.mockResolvedValue('data');
      const send1 = vi.fn();
      const send2 = vi.fn();

      streamer.subscribe('ag-001', 'ppg:1.0', send1);
      streamer.subscribe('ag-002', 'ppg:1.1', send2);

      streamer.destroy();

      expect(streamer.subscriberCount('ag-001')).toBe(0);
      expect(streamer.subscriberCount('ag-002')).toBe(0);
      expect(streamer.isPolling('ag-001')).toBe(false);
      expect(streamer.isPolling('ag-002')).toBe(false);

      // No more polling after destroy
      await vi.advanceTimersByTimeAsync(1000);
      expect(mockCapture).not.toHaveBeenCalled();
    });
  });
});
