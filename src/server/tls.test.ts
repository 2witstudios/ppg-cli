import { describe, test, expect, beforeEach, afterEach, vi } from 'vitest';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { ensureTls, getLanIps, buildPairingUrl } from './tls.js';
import {
  tlsCaKeyPath,
  tlsCaCertPath,
  tlsServerKeyPath,
  tlsServerCertPath,
} from '../lib/paths.js';

vi.setConfig({ testTimeout: 30_000 });

let tmpDir: string;

beforeEach(() => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ppg-tls-test-'));
});

afterEach(() => {
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

describe('ensureTls', () => {
  test('generates valid PEM certificates', () => {
    const bundle = ensureTls(tmpDir);

    expect(bundle.caCert).toMatch(/^-----BEGIN CERTIFICATE-----/);
    expect(bundle.caCert).toMatch(/-----END CERTIFICATE-----\n$/);
    expect(bundle.caKey).toMatch(/^-----BEGIN PRIVATE KEY-----/);
    expect(bundle.serverCert).toMatch(/^-----BEGIN CERTIFICATE-----/);
    expect(bundle.serverKey).toMatch(/^-----BEGIN PRIVATE KEY-----/);
  });

  test('CA cert has cA:TRUE and ~10 year validity', () => {
    const bundle = ensureTls(tmpDir);
    const ca = new crypto.X509Certificate(bundle.caCert);

    expect(ca.subject).toBe('CN=ppg-ca');
    expect(ca.issuer).toBe('CN=ppg-ca');
    expect(ca.ca).toBe(true);

    const notAfter = new Date(ca.validTo);
    const yearsFromNow = (notAfter.getTime() - Date.now()) / (1000 * 60 * 60 * 24 * 365);
    expect(yearsFromNow).toBeGreaterThan(9);
    expect(yearsFromNow).toBeLessThan(11);
  });

  test('server cert is signed by CA with ~1 year validity', () => {
    const bundle = ensureTls(tmpDir);
    const ca = new crypto.X509Certificate(bundle.caCert);
    const server = new crypto.X509Certificate(bundle.serverCert);

    expect(server.subject).toBe('CN=ppg-server');
    expect(server.issuer).toBe('CN=ppg-ca');
    expect(server.verify(ca.publicKey)).toBe(true);
    expect(server.ca).toBe(false);

    const notAfter = new Date(server.validTo);
    const daysFromNow = (notAfter.getTime() - Date.now()) / (1000 * 60 * 60 * 24);
    expect(daysFromNow).toBeGreaterThan(360);
    expect(daysFromNow).toBeLessThan(370);
  });

  test('server cert includes correct SANs', () => {
    const bundle = ensureTls(tmpDir);
    const server = new crypto.X509Certificate(bundle.serverCert);
    const sanStr = server.subjectAltName ?? '';

    expect(sanStr).toContain('IP Address:127.0.0.1');

    for (const ip of bundle.sans) {
      expect(sanStr).toContain(`IP Address:${ip}`);
    }
  });

  test('persists files with correct permissions', () => {
    ensureTls(tmpDir);

    const files = [
      tlsCaKeyPath(tmpDir),
      tlsCaCertPath(tmpDir),
      tlsServerKeyPath(tmpDir),
      tlsServerCertPath(tmpDir),
    ];

    for (const f of files) {
      expect(fs.existsSync(f)).toBe(true);
      const stat = fs.statSync(f);
      expect(stat.mode & 0o777).toBe(0o600);
    }
  });

  test('reuses valid certs without rewriting', async () => {
    const bundle1 = ensureTls(tmpDir);
    const mtime1 = fs.statSync(tlsCaCertPath(tmpDir)).mtimeMs;

    // Small delay to ensure mtime would differ if rewritten
    await new Promise((r) => setTimeout(r, 50));

    const bundle2 = ensureTls(tmpDir);
    const mtime2 = fs.statSync(tlsCaCertPath(tmpDir)).mtimeMs;

    expect(bundle2.caFingerprint).toBe(bundle1.caFingerprint);
    expect(bundle2.caCert).toBe(bundle1.caCert);
    expect(bundle2.serverCert).toBe(bundle1.serverCert);
    expect(mtime2).toBe(mtime1);
  });

  test('regenerates server cert when SAN is missing', () => {
    const bundle1 = ensureTls(tmpDir);

    // Replace server cert with CA cert (has no SANs matching LAN IPs)
    fs.writeFileSync(tlsServerCertPath(tmpDir), bundle1.caCert, { mode: 0o600 });

    const bundle2 = ensureTls(tmpDir);

    // CA should be preserved
    expect(bundle2.caCert).toBe(bundle1.caCert);
    expect(bundle2.caFingerprint).toBe(bundle1.caFingerprint);

    // Server cert should be regenerated
    expect(bundle2.serverCert).not.toBe(bundle1.caCert);
    const server = new crypto.X509Certificate(bundle2.serverCert);
    expect(server.subject).toBe('CN=ppg-server');
  });

  test('regenerates server cert when signed by a different CA', () => {
    const bundle1 = ensureTls(tmpDir);
    const otherDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ppg-tls-test-other-'));

    try {
      const otherBundle = ensureTls(otherDir);
      fs.writeFileSync(tlsServerCertPath(tmpDir), otherBundle.serverCert, { mode: 0o600 });
      fs.writeFileSync(tlsServerKeyPath(tmpDir), otherBundle.serverKey, { mode: 0o600 });

      const bundle2 = ensureTls(tmpDir);
      const ca = new crypto.X509Certificate(bundle1.caCert);
      const server = new crypto.X509Certificate(bundle2.serverCert);

      expect(bundle2.caFingerprint).toBe(bundle1.caFingerprint);
      expect(server.verify(ca.publicKey)).toBe(true);
      expect(bundle2.serverCert).not.toBe(otherBundle.serverCert);
    } finally {
      fs.rmSync(otherDir, { recursive: true, force: true });
    }
  });

  test('regenerates server cert when server key does not match cert', () => {
    const bundle1 = ensureTls(tmpDir);
    const { privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
    const wrongKey = privateKey.export({ type: 'pkcs8', format: 'pem' }) as string;
    fs.writeFileSync(tlsServerKeyPath(tmpDir), wrongKey, { mode: 0o600 });

    const bundle2 = ensureTls(tmpDir);
    const server = new crypto.X509Certificate(bundle2.serverCert);

    expect(bundle2.caFingerprint).toBe(bundle1.caFingerprint);
    expect(bundle2.serverKey).not.toBe(wrongKey);
    expect(server.checkPrivateKey(crypto.createPrivateKey(bundle2.serverKey))).toBe(true);
  });

  test('regenerates everything when CA cert file is missing', () => {
    const bundle1 = ensureTls(tmpDir);

    fs.unlinkSync(tlsCaCertPath(tmpDir));

    const bundle2 = ensureTls(tmpDir);

    expect(bundle2.caFingerprint).not.toBe(bundle1.caFingerprint);
  });

  test('regenerates everything when CA key does not match CA cert', () => {
    const bundle1 = ensureTls(tmpDir);
    const { privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
    const wrongCaKey = privateKey.export({ type: 'pkcs8', format: 'pem' }) as string;
    fs.writeFileSync(tlsCaKeyPath(tmpDir), wrongCaKey, { mode: 0o600 });

    const bundle2 = ensureTls(tmpDir);

    expect(bundle2.caFingerprint).not.toBe(bundle1.caFingerprint);
  });

  test('regenerates everything when PEM files contain garbage', () => {
    ensureTls(tmpDir);

    // Corrupt both cert files with garbage
    fs.writeFileSync(tlsCaCertPath(tmpDir), 'not a cert', { mode: 0o600 });
    fs.writeFileSync(tlsServerCertPath(tmpDir), 'also garbage', { mode: 0o600 });

    // Should regenerate without throwing
    const bundle = ensureTls(tmpDir);

    expect(bundle.caCert).toMatch(/^-----BEGIN CERTIFICATE-----/);
    const ca = new crypto.X509Certificate(bundle.caCert);
    expect(ca.subject).toBe('CN=ppg-ca');
  });

  test('CA fingerprint is colon-delimited SHA-256 hex', () => {
    const bundle = ensureTls(tmpDir);

    // Format: XX:XX:XX:... (32 hex pairs with colons)
    expect(bundle.caFingerprint).toMatch(/^([0-9A-F]{2}:){31}[0-9A-F]{2}$/);
  });

  test('CA fingerprint is stable across calls', () => {
    const bundle1 = ensureTls(tmpDir);
    const bundle2 = ensureTls(tmpDir);

    expect(bundle2.caFingerprint).toBe(bundle1.caFingerprint);
  });
});

describe('getLanIps', () => {
  test('always includes 127.0.0.1', () => {
    const ips = getLanIps();
    expect(ips).toContain('127.0.0.1');
  });

  test('returns only IPv4 addresses', () => {
    const ips = getLanIps();
    for (const ip of ips) {
      expect(ip).toMatch(/^\d+\.\d+\.\d+\.\d+$/);
    }
  });
});

describe('buildPairingUrl', () => {
  test('formats ppg:// URL with query params', () => {
    const url = buildPairingUrl({
      host: '192.168.1.5',
      port: 3000,
      caFingerprint: 'AA:BB:CC',
      token: 'tok123',
    });

    expect(url).toBe('ppg://connect?host=192.168.1.5&port=3000&ca=AA%3ABB%3ACC&token=tok123');
  });

  test('encodes special characters in params', () => {
    const url = buildPairingUrl({
      host: '10.0.0.1',
      port: 443,
      caFingerprint: 'AA:BB',
      token: 'a b+c',
    });

    expect(url).toContain('token=a+b%2Bc');
  });
});
