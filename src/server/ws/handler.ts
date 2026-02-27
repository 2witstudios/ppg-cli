import { URL } from 'node:url';
import type { Server as HttpServer, IncomingMessage } from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
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
  const { server, validateToken, onTerminalInput } = options;

  const wss = new WebSocketServer({ noServer: true, maxPayload: MAX_PAYLOAD });
  const clients = new Set<ClientState>();

  function sendEvent(client: ClientState, event: ServerEvent): void {
    if (client.ws.readyState === WebSocket.OPEN) {
      client.ws.send(serializeEvent(event));
    }
  }

  function broadcast(event: ServerEvent): void {
    const data = serializeEvent(event);
    for (const client of clients) {
      if (client.ws.readyState === WebSocket.OPEN) {
        client.ws.send(data);
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
        break;

      case 'terminal:unsubscribe':
        client.subscribedAgents.delete(command.agentId);
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
    }
  }

  function onUpgrade(request: IncomingMessage, socket: Duplex, head: Buffer): void {
    const url = new URL(request.url ?? '/', `http://${request.headers.host ?? 'localhost'}`);

    if (url.pathname !== '/ws') {
      socket.destroy();
      return;
    }

    const token = url.searchParams.get('token');
    if (!token) {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      return;
    }

    Promise.resolve(validateToken(token))
      .then((valid) => {
        if (!valid) {
          socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
          socket.destroy();
          return;
        }

        wss.handleUpgrade(request, socket, head, (ws) => {
          wss.emit('connection', ws, request);
        });
      })
      .catch(() => {
        socket.write('HTTP/1.1 500 Internal Server Error\r\n\r\n');
        socket.destroy();
      });
  }

  server.on('upgrade', onUpgrade);

  wss.on('connection', (ws: WebSocket) => {
    const client: ClientState = {
      ws,
      subscribedAgents: new Set(),
    };
    clients.add(client);

    ws.on('message', (raw: Buffer | string) => {
      const data = typeof raw === 'string' ? raw : raw.toString('utf-8');
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
