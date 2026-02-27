import { describe, test, expect, afterEach } from 'vitest';
import http from 'node:http';
import { WebSocket, type RawData } from 'ws';
import { createWsHandler, type WsHandler } from './handler.js';
import { parseCommand, serializeEvent, type ServerEvent } from './events.js';

// --- Helpers ---

function createTestServer(): http.Server {
  return http.createServer((_req, res) => {
    res.writeHead(404);
    res.end();
  });
}

function listen(server: http.Server): Promise<number> {
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      const addr = server.address();
      if (typeof addr === 'object' && addr !== null) {
        resolve(addr.port);
      }
    });
  });
}

function closeServer(server: http.Server): Promise<void> {
  return new Promise((resolve) => {
    server.close(() => resolve());
  });
}

function connectWs(port: number, token: string): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/ws?token=${token}`);
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

function waitForMessage(ws: WebSocket): Promise<ServerEvent> {
  return new Promise((resolve) => {
    ws.once('message', (data: RawData) => {
      const str = (() => {
        if (typeof data === 'string') return data;
        if (Buffer.isBuffer(data)) return data.toString('utf-8');
        if (data instanceof ArrayBuffer) return Buffer.from(data).toString('utf-8');
        if (Array.isArray(data)) return Buffer.concat(data).toString('utf-8');
        return '';
      })();
      resolve(JSON.parse(str) as ServerEvent);
    });
  });
}

/** Wait for a ws client to close or error (rejected upgrades emit error then close) */
function waitForDisconnect(ws: WebSocket): Promise<void> {
  return new Promise((resolve) => {
    if (ws.readyState === WebSocket.CLOSED) {
      resolve();
      return;
    }
    ws.on('close', () => resolve());
    ws.on('error', () => {
      if (ws.readyState === WebSocket.CLOSED) resolve();
    });
  });
}

function send(ws: WebSocket, obj: Record<string, unknown>): void {
  ws.send(JSON.stringify(obj));
}

/** Send a ping and wait for pong — acts as a deterministic sync barrier. */
async function roundTrip(ws: WebSocket): Promise<void> {
  const msg = waitForMessage(ws);
  send(ws, { type: 'ping' });
  await msg;
}

// --- Tests ---

describe('WebSocket handler', () => {
  let server: http.Server;
  let handler: WsHandler;
  const openSockets: WebSocket[] = [];

  async function setup(
    opts: {
      validateToken?: (token: string) => boolean | Promise<boolean>;
      onTerminalInput?: (agentId: string, data: string) => void | Promise<void>;
    } = {},
  ): Promise<number> {
    server = createTestServer();
    const port = await listen(server);
    handler = createWsHandler({
      server,
      validateToken: opts.validateToken ?? ((t) => t === 'valid-token'),
      onTerminalInput: opts.onTerminalInput,
    });
    return port;
  }

  async function connect(port: number, token = 'valid-token'): Promise<WebSocket> {
    const ws = await connectWs(port, token);
    openSockets.push(ws);
    return ws;
  }

  afterEach(async () => {
    for (const ws of openSockets) {
      if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
        ws.close();
      }
    }
    openSockets.length = 0;

    if (handler) {
      await handler.close().catch(() => {});
    }
    if (server?.listening) {
      await closeServer(server);
    }
  });

  describe('connection and auth', () => {
    test('accepts connection with valid token', async () => {
      const port = await setup();
      const ws = await connect(port);
      expect(ws.readyState).toBe(WebSocket.OPEN);
      expect(handler.clients.size).toBe(1);
    });

    test('rejects connection with invalid token', async () => {
      const port = await setup();
      const ws = new WebSocket(`ws://127.0.0.1:${port}/ws?token=bad-token`);
      openSockets.push(ws);

      await waitForDisconnect(ws);
      expect(handler.clients.size).toBe(0);
    });

    test('rejects connection with no token', async () => {
      const port = await setup();
      const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
      openSockets.push(ws);

      await waitForDisconnect(ws);
      expect(handler.clients.size).toBe(0);
    });

    test('rejects connection on wrong path', async () => {
      const port = await setup();
      const ws = new WebSocket(`ws://127.0.0.1:${port}/other?token=valid-token`);
      openSockets.push(ws);

      await waitForDisconnect(ws);
      expect(handler.clients.size).toBe(0);
    });

    test('supports async token validation', async () => {
      const port = await setup({
        validateToken: async (t) => t === 'async-token',
      });
      const ws = await connect(port, 'async-token');
      expect(ws.readyState).toBe(WebSocket.OPEN);
    });
  });

  describe('command dispatch', () => {
    test('responds to ping with pong', async () => {
      const port = await setup();
      const ws = await connect(port);

      const msgPromise = waitForMessage(ws);
      send(ws, { type: 'ping' });

      const event = await msgPromise;
      expect(event).toEqual({ type: 'pong' });
    });

    test('sends error for invalid JSON', async () => {
      const port = await setup();
      const ws = await connect(port);

      const msgPromise = waitForMessage(ws);
      ws.send('not json');

      const event = await msgPromise;
      expect(event.type).toBe('error');
      expect((event as { code: string }).code).toBe('INVALID_COMMAND');
    });

    test('sends error for unknown command type', async () => {
      const port = await setup();
      const ws = await connect(port);

      const msgPromise = waitForMessage(ws);
      send(ws, { type: 'unknown' });

      const event = await msgPromise;
      expect(event.type).toBe('error');
      expect((event as { code: string }).code).toBe('INVALID_COMMAND');
    });

    test('handles terminal:subscribe', async () => {
      const port = await setup();
      const ws = await connect(port);

      send(ws, { type: 'terminal:subscribe', agentId: 'ag-12345678' });
      await roundTrip(ws);

      const [client] = handler.clients;
      expect(client.subscribedAgents.has('ag-12345678')).toBe(true);
    });

    test('handles terminal:unsubscribe', async () => {
      const port = await setup();
      const ws = await connect(port);

      send(ws, { type: 'terminal:subscribe', agentId: 'ag-12345678' });
      await roundTrip(ws);

      send(ws, { type: 'terminal:unsubscribe', agentId: 'ag-12345678' });
      await roundTrip(ws);

      const [client] = handler.clients;
      expect(client.subscribedAgents.has('ag-12345678')).toBe(false);
    });

    test('handles terminal:input and calls onTerminalInput', async () => {
      let capturedAgentId = '';
      let capturedData = '';

      const port = await setup({
        onTerminalInput: (agentId, data) => {
          capturedAgentId = agentId;
          capturedData = data;
        },
      });
      const ws = await connect(port);

      send(ws, { type: 'terminal:input', agentId: 'ag-12345678', data: 'hello\n' });
      await roundTrip(ws);

      expect(capturedAgentId).toBe('ag-12345678');
      expect(capturedData).toBe('hello\n');
    });

    test('terminal:input is a no-op when onTerminalInput is not provided', async () => {
      const port = await setup(); // no onTerminalInput
      const ws = await connect(port);

      send(ws, { type: 'terminal:input', agentId: 'ag-12345678', data: 'hello\n' });
      // Should not throw or send error — verify via round-trip
      const msg = waitForMessage(ws);
      send(ws, { type: 'ping' });
      const event = await msg;
      expect(event).toEqual({ type: 'pong' });
    });

    test('terminal:input sends error when onTerminalInput throws', async () => {
      const port = await setup({
        onTerminalInput: () => {
          throw new Error('tmux exploded');
        },
      });
      const ws = await connect(port);

      const msgPromise = waitForMessage(ws);
      send(ws, { type: 'terminal:input', agentId: 'ag-12345678', data: 'hello\n' });

      const event = await msgPromise;
      expect(event.type).toBe('error');
      expect((event as { code: string }).code).toBe('TERMINAL_INPUT_FAILED');
    });

    test('terminal:input sends error when async onTerminalInput rejects', async () => {
      const port = await setup({
        onTerminalInput: async () => {
          throw new Error('async tmux exploded');
        },
      });
      const ws = await connect(port);

      const msgPromise = waitForMessage(ws);
      send(ws, { type: 'terminal:input', agentId: 'ag-12345678', data: 'hello\n' });

      const event = await msgPromise;
      expect(event.type).toBe('error');
      expect((event as { code: string }).code).toBe('TERMINAL_INPUT_FAILED');
    });
  });

  describe('broadcast and sendEvent', () => {
    test('broadcast sends to all connected clients', async () => {
      const port = await setup();
      const ws1 = await connect(port);
      const ws2 = await connect(port);

      expect(handler.clients.size).toBe(2);

      const msg1 = waitForMessage(ws1);
      const msg2 = waitForMessage(ws2);

      handler.broadcast({
        type: 'manifest:updated',
        manifest: {
          version: 1,
          projectRoot: '/tmp',
          sessionName: 'test',
          worktrees: {},
          createdAt: '2025-01-01T00:00:00Z',
          updatedAt: '2025-01-01T00:00:00Z',
        },
      });

      const [event1, event2] = await Promise.all([msg1, msg2]);
      expect(event1.type).toBe('manifest:updated');
      expect(event2.type).toBe('manifest:updated');
    });

    test('sendEvent sends to specific client only', async () => {
      const port = await setup();
      const ws1 = await connect(port);
      const ws2 = await connect(port);

      const [client1] = handler.clients;
      handler.sendEvent(client1, { type: 'pong' });

      // ws1 should receive the pong
      const event = await waitForMessage(ws1);
      expect(event).toEqual({ type: 'pong' });

      // ws2 should have no pending messages — verify by sending a ping
      // and confirming the next message is the pong, not the earlier event
      const msg2 = waitForMessage(ws2);
      send(ws2, { type: 'ping' });
      const event2 = await msg2;
      expect(event2).toEqual({ type: 'pong' });
    });

    test('sendEvent skips client with closed socket', async () => {
      const port = await setup();
      const ws = await connect(port);

      const [client] = handler.clients;
      ws.close();
      await waitForDisconnect(ws);

      // Should not throw when sending to a closed client
      handler.sendEvent(client, { type: 'pong' });
    });
  });

  describe('cleanup', () => {
    test('removes client on disconnect', async () => {
      const port = await setup();
      const ws = await connect(port);

      expect(handler.clients.size).toBe(1);

      ws.close();
      await waitForDisconnect(ws);
      // Use a round-trip on a second connection as a sync barrier
      const ws2 = await connect(port);
      await roundTrip(ws2);

      expect(handler.clients.size).toBe(1); // only ws2 remains
    });

    test('close() terminates all clients', async () => {
      const port = await setup();
      const ws1 = await connect(port);
      const ws2 = await connect(port);

      const close1 = waitForDisconnect(ws1);
      const close2 = waitForDisconnect(ws2);

      await handler.close();
      await Promise.all([close1, close2]);

      expect(handler.clients.size).toBe(0);
    });

    test('close() removes upgrade listener from server', async () => {
      const port = await setup();
      await handler.close();

      // After close, a new WS connection attempt should not be handled
      const ws = new WebSocket(`ws://127.0.0.1:${port}/ws?token=valid-token`);
      openSockets.push(ws);

      await waitForDisconnect(ws);
      expect(handler.clients.size).toBe(0);
    });
  });
});

describe('parseCommand', () => {
  test('parses ping command', () => {
    expect(parseCommand('{"type":"ping"}')).toEqual({ type: 'ping' });
  });

  test('parses terminal:subscribe', () => {
    expect(parseCommand('{"type":"terminal:subscribe","agentId":"ag-123"}')).toEqual({
      type: 'terminal:subscribe',
      agentId: 'ag-123',
    });
  });

  test('parses terminal:unsubscribe', () => {
    expect(parseCommand('{"type":"terminal:unsubscribe","agentId":"ag-123"}')).toEqual({
      type: 'terminal:unsubscribe',
      agentId: 'ag-123',
    });
  });

  test('parses terminal:input', () => {
    expect(parseCommand('{"type":"terminal:input","agentId":"ag-123","data":"ls\\n"}')).toEqual({
      type: 'terminal:input',
      agentId: 'ag-123',
      data: 'ls\n',
    });
  });

  test('returns null for invalid JSON', () => {
    expect(parseCommand('not json')).toBeNull();
  });

  test('returns null for unknown type', () => {
    expect(parseCommand('{"type":"unknown"}')).toBeNull();
  });

  test('returns null for missing required fields', () => {
    expect(parseCommand('{"type":"terminal:subscribe"}')).toBeNull();
    expect(parseCommand('{"type":"terminal:input","agentId":"ag-123"}')).toBeNull();
  });

  test('returns null for non-object', () => {
    expect(parseCommand('"string"')).toBeNull();
    expect(parseCommand('42')).toBeNull();
    expect(parseCommand('null')).toBeNull();
  });
});

describe('serializeEvent', () => {
  test('serializes pong event', () => {
    expect(serializeEvent({ type: 'pong' })).toBe('{"type":"pong"}');
  });

  test('serializes error event', () => {
    const event: ServerEvent = { type: 'error', code: 'TEST', message: 'msg' };
    const parsed = JSON.parse(serializeEvent(event));
    expect(parsed).toEqual({ type: 'error', code: 'TEST', message: 'msg' });
  });

  test('serializes terminal:output event', () => {
    const event: ServerEvent = { type: 'terminal:output', agentId: 'ag-1', data: 'hello' };
    const parsed = JSON.parse(serializeEvent(event));
    expect(parsed).toEqual({ type: 'terminal:output', agentId: 'ag-1', data: 'hello' });
  });
});
