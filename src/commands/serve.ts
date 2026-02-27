import fs from 'node:fs/promises';
import fsSync from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { createServer } from 'node:https';
import { execSync } from 'node:child_process';
import { randomBytes, generateKeyPairSync, X509Certificate } from 'node:crypto';
import qrcode from 'qrcode-terminal';
import { getRepoRoot } from '../core/worktree.js';
import { ppgDir } from '../lib/paths.js';
import { NotInitializedError } from '../lib/errors.js';
import { output, info, success } from '../lib/output.js';

export interface ServeOptions {
  port?: number;
  host?: string;
  daemon?: boolean;
  json?: boolean;
}

const DEFAULT_PORT = 7700;
const DEFAULT_HOST = '0.0.0.0';

interface TlsCredentials {
  key: string;
  cert: string;
  fingerprint: string;
}

async function ensureTlsCerts(projectRoot: string): Promise<TlsCredentials> {
  const certsDir = path.join(ppgDir(projectRoot), 'certs');
  const keyPath = path.join(certsDir, 'server.key');
  const certPath = path.join(certsDir, 'server.crt');

  try {
    const [key, cert] = await Promise.all([
      fs.readFile(keyPath, 'utf-8'),
      fs.readFile(certPath, 'utf-8'),
    ]);
    const fingerprint = getCertFingerprint(cert);
    return { key, cert, fingerprint };
  } catch {
    // Generate self-signed certificate
    await fs.mkdir(certsDir, { recursive: true });

    const { privateKey } = generateKeyPairSync('ec', {
      namedCurve: 'prime256v1',
    });

    const keyPem = privateKey.export({ type: 'sec1', format: 'pem' }) as string;
    const certPem = generateSelfSignedCert(keyPem);

    await Promise.all([
      fs.writeFile(keyPath, keyPem, { mode: 0o600 }),
      fs.writeFile(certPath, certPem),
    ]);

    const fingerprint = getCertFingerprint(certPem);
    return { key: keyPem, cert: certPem, fingerprint };
  }
}

function generateSelfSignedCert(keyPem: string): string {
  const tmpKey = path.join(os.tmpdir(), `ppg-key-${process.pid}.pem`);
  const tmpCert = path.join(os.tmpdir(), `ppg-cert-${process.pid}.pem`);

  try {
    fsSync.writeFileSync(tmpKey, keyPem, { mode: 0o600 });
    execSync(
      `openssl req -new -x509 -key "${tmpKey}" -out "${tmpCert}" -days 365 -subj "/CN=ppg-server" -addext "subjectAltName=IP:127.0.0.1,IP:::1"`,
      { stdio: 'pipe' },
    );
    return fsSync.readFileSync(tmpCert, 'utf-8');
  } finally {
    try { fsSync.unlinkSync(tmpKey); } catch {}
    try { fsSync.unlinkSync(tmpCert); } catch {}
  }
}

function getCertFingerprint(certPem: string): string {
  const x509 = new X509Certificate(certPem);
  return x509.fingerprint256;
}

function generateToken(): string {
  return randomBytes(32).toString('base64url');
}

function buildPairingUrl(params: {
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

function getLocalIp(): string {
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
  const manifestFile = path.join(ppgDir(projectRoot), 'manifest.json');
  try {
    await fs.access(manifestFile);
  } catch {
    throw new NotInitializedError(projectRoot);
  }

  const port = options.port ?? DEFAULT_PORT;
  const host = options.host ?? DEFAULT_HOST;
  const isDaemon = options.daemon ?? false;
  const isInteractive = process.stdout.isTTY && !isDaemon;

  // Generate TLS credentials and auth token
  const tls = await ensureTlsCerts(projectRoot);
  const token = generateToken();

  // Resolve the display host for pairing URL
  const displayHost = host === '0.0.0.0' ? getLocalIp() : host;
  const pairingUrl = buildPairingUrl({
    host: displayHost,
    port,
    fingerprint: tls.fingerprint,
    token,
  });

  // Create HTTPS server
  const server = createServer({ key: tls.key, cert: tls.cert }, (req, res) => {
    const authHeader = req.headers.authorization;
    if (authHeader !== `Bearer ${token}`) {
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
