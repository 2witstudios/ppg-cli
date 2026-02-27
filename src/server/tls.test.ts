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
  test('generates valid PEM certificates', async () => {
    const bundle = await ensureTls(tmpDir);

    expect(bundle.caCert).toMatch(/^-----BEGIN CERTIFICATE-----/);
    expect(bundle.caCert).toMatch(/-----END CERTIFICATE-----\n$/);
    expect(bundle.caKey).toMatch(/^-----BEGIN PRIVATE KEY-----/);
    expect(bundle.serverCert).toMatch(/^-----BEGIN CERTIFICATE-----/);
    expect(bundle.serverKey).toMatch(/^-----BEGIN PRIVATE KEY-----/);
  });

  test('CA cert has cA:TRUE and ~10 year validity', async () => {
    const bundle = await ensureTls(tmpDir);
    const ca = new crypto.X509Certificate(bundle.caCert);

    expect(ca.subject).toBe('CN=ppg-ca');
    expect(ca.issuer).toBe('CN=ppg-ca');
    expect(ca.ca).toBe(true);

    const notAfter = new Date(ca.validTo);
    const yearsFromNow = (notAfter.getTime() - Date.now()) / (1000 * 60 * 60 * 24 * 365);
    expect(yearsFromNow).toBeGreaterThan(9);
    expect(yearsFromNow).toBeLessThan(11);
  });

  test('server cert is signed by CA with ~1 year validity', async () => {
    const bundle = await ensureTls(tmpDir);
    const ca = new crypto.X509Certificate(bundle.caCert);
    const server = new crypto.X509Certificate(bundle.serverCert);

    expect(server.subject).toBe('CN=ppg-server');
    expect(server.issuer).toBe('CN=ppg-ca');
    expect(server.checkIssued(ca)).toBe(true);
    expect(server.ca).toBe(false);

    const notAfter = new Date(server.validTo);
    const daysFromNow = (notAfter.getTime() - Date.now()) / (1000 * 60 * 60 * 24);
    expect(daysFromNow).toBeGreaterThan(360);
    expect(daysFromNow).toBeLessThan(370);
  });

  test('server cert includes correct SANs', async () => {
    const bundle = await ensureTls(tmpDir);
    const server = new crypto.X509Certificate(bundle.serverCert);
    const sanStr = server.subjectAltName ?? '';

    // Must include 127.0.0.1
    expect(sanStr).toContain('IP Address:127.0.0.1');

    // All reported SANs should match
    for (const ip of bundle.sans) {
      expect(sanStr).toContain(`IP Address:${ip}`);
    }
  });

  test('persists files with correct permissions', async () => {
    await ensureTls(tmpDir);

    const files = [
      tlsCaKeyPath(tmpDir),
      tlsCaCertPath(tmpDir),
      tlsServerKeyPath(tmpDir),
      tlsServerCertPath(tmpDir),
    ];

    for (const f of files) {
      expect(fs.existsSync(f)).toBe(true);
      const stat = fs.statSync(f);
      // Owner read+write (0o600 = 384 decimal), mask out non-permission bits
      expect(stat.mode & 0o777).toBe(0o600);
    }
  });

  test('reuses valid certs without rewriting', async () => {
    const bundle1 = await ensureTls(tmpDir);
    const mtime1 = fs.statSync(tlsCaCertPath(tmpDir)).mtimeMs;

    // Small delay to ensure mtime would differ
    await new Promise((r) => setTimeout(r, 50));

    const bundle2 = await ensureTls(tmpDir);
    const mtime2 = fs.statSync(tlsCaCertPath(tmpDir)).mtimeMs;

    expect(bundle2.caFingerprint).toBe(bundle1.caFingerprint);
    expect(bundle2.caCert).toBe(bundle1.caCert);
    expect(bundle2.serverCert).toBe(bundle1.serverCert);
    expect(mtime2).toBe(mtime1);
  });

  test('regenerates server cert when SAN is missing', async () => {
    const bundle1 = await ensureTls(tmpDir);

    // Overwrite server cert with one that has no SANs (corrupt it by removing SANs)
    // Easiest: write a cert with a bogus SAN that won't match current IPs
    const serverCertPath = tlsServerCertPath(tmpDir);
    // Replace server cert content with CA cert (wrong SANs)
    fs.writeFileSync(serverCertPath, bundle1.caCert, { mode: 0o600 });

    const bundle2 = await ensureTls(tmpDir);

    // CA should be preserved
    expect(bundle2.caCert).toBe(bundle1.caCert);
    expect(bundle2.caFingerprint).toBe(bundle1.caFingerprint);

    // Server cert should be regenerated (different from CA cert)
    expect(bundle2.serverCert).not.toBe(bundle1.caCert);
    const server = new crypto.X509Certificate(bundle2.serverCert);
    expect(server.subject).toBe('CN=ppg-server');
  });

  test('regenerates everything when CA cert file is missing', async () => {
    const bundle1 = await ensureTls(tmpDir);

    // Delete CA cert
    fs.unlinkSync(tlsCaCertPath(tmpDir));

    const bundle2 = await ensureTls(tmpDir);

    // Should have new CA
    expect(bundle2.caFingerprint).not.toBe(bundle1.caFingerprint);
  });

  test('CA fingerprint is colon-delimited SHA-256 hex', async () => {
    const bundle = await ensureTls(tmpDir);

    // Format: XX:XX:XX:... (32 hex pairs with colons)
    expect(bundle.caFingerprint).toMatch(/^([0-9A-F]{2}:){31}[0-9A-F]{2}$/);
  });

  test('CA fingerprint is stable across calls', async () => {
    const bundle1 = await ensureTls(tmpDir);
    const bundle2 = await ensureTls(tmpDir);

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
