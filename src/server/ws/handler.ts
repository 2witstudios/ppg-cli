import { URL } from 'node:url';
import type { Server as HttpServer, IncomingMessage } from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import type { RawData } from 'ws';
import type { Duplex } from 'node:stream';
import {
  parseCommand,
  serializeEvent,
  type ClientCommand,
  type ServerEvent,
} from './events.js';

// --- Client State ---

export interface ClientState {
  ws: WebSocket;
  subscribedAgents: Set<string>;
}

// --- Handler Options ---

export interface WsHandlerOptions {
  server: HttpServer;
  validateToken: (token: string) => boolean | Promise<boolean>;
  onTerminalInput?: (agentId: string, data: string) => void | Promise<void>;
  onTerminalResize?: (agentId: string, cols: number, rows: number) => void | Promise<void>;
  onTerminalSubscribe?: (client: ClientState, agentId: string) => void;
  onTerminalUnsubscribe?: (client: ClientState, agentId: string) => void;
}

// --- WebSocket Handler ---

export interface WsHandler {
  wss: WebSocketServer;
  clients: Set<ClientState>;
  broadcast: (event: ServerEvent) => void;
  sendEvent: (client: ClientState, event: ServerEvent) => void;
  close: () => Promise<void>;
}

const MAX_PAYLOAD = 65_536; // 64 KB

export function createWsHandler(options: WsHandlerOptions): WsHandler {
  const { server, validateToken, onTerminalInput, onTerminalResize, onTerminalSubscribe, onTerminalUnsubscribe } = options;

  const wss = new WebSocketServer({ noServer: true, maxPayload: MAX_PAYLOAD });
  const clients = new Set<ClientState>();

  function sendData(ws: WebSocket, data: string): boolean {
    if (ws.readyState !== WebSocket.OPEN) return false;
    try {
      ws.send(data);
      return true;
    } catch {
      return false;
    }
  }

  function decodeRawData(raw: RawData): string {
    if (typeof raw === 'string') return raw;
    if (Buffer.isBuffer(raw)) return raw.toString('utf-8');
    if (raw instanceof ArrayBuffer) return Buffer.from(raw).toString('utf-8');
    if (Array.isArray(raw)) return Buffer.concat(raw).toString('utf-8');
    return '';
  }

  function rejectUpgrade(socket: Duplex, statusLine: string): void {
    if (socket.destroyed) return;
    try {
      socket.write(`${statusLine}\r\nConnection: close\r\n\r\n`);
    } catch {
      // ignore write errors on broken sockets
    } finally {
      socket.destroy();
    }
  }

  function sendEvent(client: ClientState, event: ServerEvent): void {
    if (!sendData(client.ws, serializeEvent(event))) {
      clients.delete(client);
    }
  }

  function broadcast(event: ServerEvent): void {
    const data = serializeEvent(event);
    for (const client of clients) {
      if (!sendData(client.ws, data)) {
        clients.delete(client);
      }
    }
  }

  function handleCommand(client: ClientState, command: ClientCommand): void {
    switch (command.type) {
      case 'ping':
        sendEvent(client, { type: 'pong' });
        break;

      case 'terminal:subscribe':
        client.subscribedAgents.add(command.agentId);
        onTerminalSubscribe?.(client, command.agentId);
        break;

      case 'terminal:unsubscribe':
        client.subscribedAgents.delete(command.agentId);
        onTerminalUnsubscribe?.(client, command.agentId);
        break;

      case 'terminal:input':
        if (onTerminalInput) {
          try {
            Promise.resolve(onTerminalInput(command.agentId, command.data)).catch(() => {
              sendEvent(client, {
                type: 'error',
                code: 'TERMINAL_INPUT_FAILED',
                message: `Failed to send input to agent ${command.agentId}`,
              });
            });
          } catch {
            sendEvent(client, {
              type: 'error',
              code: 'TERMINAL_INPUT_FAILED',
              message: `Failed to send input to agent ${command.agentId}`,
            });
          }
        }
        break;

      case 'terminal:resize':
        if (onTerminalResize) {
          try {
            Promise.resolve(onTerminalResize(command.agentId, command.cols, command.rows)).catch(() => {});
          } catch {
            // Best-effort resize, no error sent to client
          }
        }
        break;
    }
  }

  function onUpgrade(request: IncomingMessage, socket: Duplex, head: Buffer): void {
    let url: URL;
    try {
      // The path/query in request.url is all we need; avoid trusting Host header.
      url = new URL(request.url ?? '/', 'http://localhost');
    } catch {
      rejectUpgrade(socket, 'HTTP/1.1 400 Bad Request');
      return;
    }

    if (url.pathname !== '/ws') {
      rejectUpgrade(socket, 'HTTP/1.1 404 Not Found');
      return;
    }

    const token = url.searchParams.get('token');
    if (!token) {
      rejectUpgrade(socket, 'HTTP/1.1 401 Unauthorized');
      return;
    }

    Promise.resolve(validateToken(token))
      .then((valid) => {
        if (socket.destroyed) return;
        if (!valid) {
          rejectUpgrade(socket, 'HTTP/1.1 401 Unauthorized');
          return;
        }

        try {
          wss.handleUpgrade(request, socket, head, (ws) => {
            wss.emit('connection', ws, request);
          });
        } catch {
          rejectUpgrade(socket, 'HTTP/1.1 500 Internal Server Error');
        }
      })
      .catch(() => {
        rejectUpgrade(socket, 'HTTP/1.1 500 Internal Server Error');
      });
  }

  server.on('upgrade', onUpgrade);

  wss.on('connection', (ws: WebSocket) => {
    const client: ClientState = {
      ws,
      subscribedAgents: new Set(),
    };
    clients.add(client);

    ws.on('message', (raw: RawData) => {
      const data = decodeRawData(raw);
      const command = parseCommand(data);

      if (!command) {
        sendEvent(client, {
          type: 'error',
          code: 'INVALID_COMMAND',
          message: 'Could not parse command',
        });
        return;
      }

      handleCommand(client, command);
    });

    ws.on('close', () => {
      if (onTerminalUnsubscribe) {
        for (const agentId of client.subscribedAgents) {
          onTerminalUnsubscribe(client, agentId);
        }
      }
      clients.delete(client);
    });

    ws.on('error', () => {
      clients.delete(client);
    });
  });

  async function close(): Promise<void> {
    server.removeListener('upgrade', onUpgrade);
    for (const client of clients) {
      client.ws.close(1001, 'Server shutting down');
    }
    await new Promise<void>((resolve, reject) => {
      wss.close((err) => (err ? reject(err) : resolve()));
    });
    clients.clear();
  }

  return { wss, clients, broadcast, sendEvent, close };
}
