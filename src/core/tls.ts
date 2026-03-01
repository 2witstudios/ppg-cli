import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { generateKeyPairSync, X509Certificate } from 'node:crypto';
import { execa } from 'execa';
import { ppgDir } from '../lib/paths.js';
import { execaEnv } from '../lib/env.js';

export interface TlsCredentials {
  key: string;
  cert: string;
  fingerprint: string;
}

export async function ensureTlsCerts(projectRoot: string): Promise<TlsCredentials> {
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
  } catch (error) {
    if (!hasErrorCode(error, 'ENOENT')) {
      throw error;
    }
  }

  await fs.mkdir(certsDir, { recursive: true });

  const { privateKey } = generateKeyPairSync('ec', {
    namedCurve: 'prime256v1',
  });

  const keyPem = privateKey.export({ type: 'sec1', format: 'pem' }) as string;
  const certPem = await generateSelfSignedCert(keyPem, buildSubjectAltName());

  await Promise.all([
    fs.writeFile(keyPath, keyPem, { mode: 0o600 }),
    fs.writeFile(certPath, certPem),
  ]);

  const fingerprint = getCertFingerprint(certPem);
  return { key: keyPem, cert: certPem, fingerprint };
}

async function generateSelfSignedCert(keyPem: string, subjectAltName: string): Promise<string> {
  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'ppg-tls-'));
  const tmpKey = path.join(tmpDir, 'server.key');
  const tmpCert = path.join(tmpDir, 'server.crt');

  try {
    await fs.writeFile(tmpKey, keyPem, { mode: 0o600 });
    await execa('openssl', [
      'req', '-new', '-x509',
      '-key', tmpKey,
      '-out', tmpCert,
      '-days', '365',
      '-subj', '/CN=ppg-server',
      '-addext', subjectAltName,
    ], { ...execaEnv, stdio: 'pipe' });
    return await fs.readFile(tmpCert, 'utf-8');
  } finally {
    await fs.rm(tmpDir, { recursive: true, force: true });
  }
}

function buildSubjectAltName(): string {
  const sanEntries = new Set<string>([
    'DNS:localhost',
    'IP:127.0.0.1',
    'IP:::1',
  ]);

  for (const addresses of Object.values(os.networkInterfaces())) {
    for (const iface of addresses ?? []) {
      if (iface.internal) continue;
      if (iface.family !== 'IPv4' && iface.family !== 'IPv6') continue;
      sanEntries.add(`IP:${iface.address}`);
    }
  }

  return `subjectAltName=${Array.from(sanEntries).join(',')}`;
}

function hasErrorCode(error: unknown, code: string): boolean {
  return typeof error === 'object'
    && error !== null
    && 'code' in error
    && (error as { code?: unknown }).code === code;
}

export function getCertFingerprint(certPem: string): string {
  const x509 = new X509Certificate(certPem);
  return x509.fingerprint256;
}
