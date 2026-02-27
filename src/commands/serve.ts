import os from 'node:os';
import { createServer } from 'node:https';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import qrcode from 'qrcode-terminal';
import { getRepoRoot } from '../core/worktree.js';
import { requireManifest } from '../core/manifest.js';
import { ensureTlsCerts } from '../core/tls.js';
import { output, info, success } from '../lib/output.js';

export interface ServeOptions {
  port: number;
  host: string;
  daemon?: boolean;
  json?: boolean;
}

export function buildPairingUrl(params: {
  host: string;
  port: number;
  fingerprint: string;
  token: string;
}): string {
  const { host, port, fingerprint, token } = params;
  const url = new URL('ppg://connect');
  url.searchParams.set('host', host);
  url.searchParams.set('port', String(port));
  url.searchParams.set('ca', fingerprint);
  url.searchParams.set('token', token);
  return url.toString();
}

export function getLocalIp(): string {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name] ?? []) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address;
      }
    }
  }
  return '127.0.0.1';
}

export function verifyToken(provided: string, expected: string): boolean {
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

function generateToken(): string {
  return randomBytes(32).toString('base64url');
}

function displayQrCode(pairingUrl: string): Promise<void> {
  return new Promise<void>((resolve) => {
    qrcode.generate(pairingUrl, { small: true }, (code: string) => {
      console.log('');
      console.log(code);
      resolve();
    });
  });
}

export async function serveCommand(options: ServeOptions): Promise<void> {
  const projectRoot = await getRepoRoot();
  await requireManifest(projectRoot);

  const { port, host } = options;
  const isDaemon = options.daemon ?? false;
  const isInteractive = process.stdout.isTTY && !isDaemon;

  const tls = await ensureTlsCerts(projectRoot);
  const token = generateToken();

  const displayHost = host === '0.0.0.0' ? getLocalIp() : host;
  const pairingUrl = buildPairingUrl({
    host: displayHost,
    port,
    fingerprint: tls.fingerprint,
    token,
  });

  const server = createServer({ key: tls.key, cert: tls.cert }, (req, res) => {
    const authHeader = req.headers.authorization ?? '';
    const provided = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
    if (!verifyToken(provided, token)) {
      res.writeHead(401, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Unauthorized' }));
      return;
    }

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok' }));
  });

  await new Promise<void>((resolve, reject) => {
    server.on('error', reject);
    server.listen(port, host, () => resolve());
  });

  if (options.json) {
    output({
      status: 'listening',
      host: displayHost,
      port,
      token,
      fingerprint: tls.fingerprint,
      pairingUrl,
    }, true);
  } else {
    success(`Server listening on https://${displayHost}:${port}`);
    info(`Token: ${token}`);

    if (isInteractive) {
      info('Scan QR code to pair:');
      await displayQrCode(pairingUrl);
      info(`Pairing URL: ${pairingUrl}`);
    }
  }

  // Keep running until killed
  await new Promise<void>((resolve) => {
    const shutdown = () => {
      server.close(() => resolve());
    };
    process.on('SIGINT', shutdown);
    process.on('SIGTERM', shutdown);
  });
}
