import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';

import {
  tlsDir,
  tlsCaKeyPath,
  tlsCaCertPath,
  tlsServerKeyPath,
  tlsServerCertPath,
} from '../lib/paths.js';

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export interface TlsBundle {
  caCert: string;
  caKey: string;
  serverCert: string;
  serverKey: string;
  caFingerprint: string;
  sans: string[];
}

// ---------------------------------------------------------------------------
// ASN.1 / DER primitives
// ---------------------------------------------------------------------------

function derLength(len: number): Buffer {
  if (len < 0x80) return Buffer.from([len]);
  if (len < 0x100) return Buffer.from([0x81, len]);
  if (len <= 0xffff) return Buffer.from([0x82, (len >> 8) & 0xff, len & 0xff]);
  throw new Error(`DER length ${len} exceeds 2-byte encoding`);
}

function derTlv(tag: number, value: Buffer): Buffer {
  return Buffer.concat([Buffer.from([tag]), derLength(value.length), value]);
}

function derSeq(items: Buffer[]): Buffer {
  return derTlv(0x30, Buffer.concat(items));
}

function derSet(items: Buffer[]): Buffer {
  return derTlv(0x31, Buffer.concat(items));
}

function derInteger(n: Buffer | number): Buffer {
  let buf: Buffer;
  if (typeof n === 'number') {
    // Encode small integers — used for version field (0, 2)
    if (n === 0) {
      buf = Buffer.from([0]);
    } else {
      const hex = n.toString(16);
      buf = Buffer.from(hex.length % 2 ? '0' + hex : hex, 'hex');
      if (buf[0] & 0x80) buf = Buffer.concat([Buffer.from([0]), buf]);
    }
  } else {
    buf = n;
    if (buf[0] & 0x80) buf = Buffer.concat([Buffer.from([0]), buf]);
  }
  return derTlv(0x02, buf);
}

function derOid(encoded: number[]): Buffer {
  return derTlv(0x06, Buffer.from(encoded));
}

function derUtf8(s: string): Buffer {
  return derTlv(0x0c, Buffer.from(s, 'utf8'));
}

function derUtcTime(d: Date): Buffer {
  const s =
    String(d.getUTCFullYear()).slice(2) +
    String(d.getUTCMonth() + 1).padStart(2, '0') +
    String(d.getUTCDate()).padStart(2, '0') +
    String(d.getUTCHours()).padStart(2, '0') +
    String(d.getUTCMinutes()).padStart(2, '0') +
    String(d.getUTCSeconds()).padStart(2, '0') +
    'Z';
  return derTlv(0x17, Buffer.from(s, 'ascii'));
}

function derGeneralizedTime(d: Date): Buffer {
  const s =
    String(d.getUTCFullYear()) +
    String(d.getUTCMonth() + 1).padStart(2, '0') +
    String(d.getUTCDate()).padStart(2, '0') +
    String(d.getUTCHours()).padStart(2, '0') +
    String(d.getUTCMinutes()).padStart(2, '0') +
    String(d.getUTCSeconds()).padStart(2, '0') +
    'Z';
  return derTlv(0x18, Buffer.from(s, 'ascii'));
}

function derBitString(data: Buffer): Buffer {
  // Prepend 0x00 (unused-bits count)
  return derTlv(0x03, Buffer.concat([Buffer.from([0]), data]));
}

function derNull(): Buffer {
  return Buffer.from([0x05, 0x00]);
}

/** Context-tagged explicit wrapper: [tagNum] EXPLICIT */
function derContextExplicit(tagNum: number, inner: Buffer): Buffer {
  return derTlv(0xa0 | tagNum, inner);
}

/** Context-tagged OCTET STRING wrapper */
function derContextOctetString(tagNum: number, inner: Buffer): Buffer {
  return derTlv(0x80 | tagNum, inner);
}

// ---------------------------------------------------------------------------
// OIDs
// ---------------------------------------------------------------------------

// sha256WithRSAEncryption 1.2.840.113549.1.1.11
const OID_SHA256_RSA = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b];
// commonName 2.5.4.3
const OID_CN = [0x55, 0x04, 0x03];
// basicConstraints 2.5.29.19
const OID_BASIC_CONSTRAINTS = [0x55, 0x1d, 0x13];
// keyUsage 2.5.29.15
const OID_KEY_USAGE = [0x55, 0x1d, 0x0f];
// subjectAltName 2.5.29.17
const OID_SAN = [0x55, 0x1d, 0x11];

// ---------------------------------------------------------------------------
// Structural helpers
// ---------------------------------------------------------------------------

function buildAlgorithmIdentifier(): Buffer {
  return derSeq([derOid(OID_SHA256_RSA), derNull()]);
}

function buildName(cn: string): Buffer {
  const rdn = derSet([derSeq([derOid(OID_CN), derUtf8(cn)])]);
  return derSeq([rdn]);
}

function buildValidity(from: Date, to: Date): Buffer {
  // Use UTCTime for dates before 2050, GeneralizedTime otherwise
  const encodeTime = (d: Date) =>
    d.getUTCFullYear() < 2050 ? derUtcTime(d) : derGeneralizedTime(d);
  return derSeq([encodeTime(from), encodeTime(to)]);
}

function buildBasicConstraintsExt(isCA: boolean, critical: boolean): Buffer {
  const value = derSeq(isCA ? [derTlv(0x01, Buffer.from([0xff]))] : []);
  const octetValue = derTlv(0x04, value);
  const parts: Buffer[] = [derOid(OID_BASIC_CONSTRAINTS)];
  if (critical) parts.push(derTlv(0x01, Buffer.from([0xff])));
  parts.push(octetValue);
  return derSeq(parts);
}

function buildKeyUsageExt(isCA: boolean, critical: boolean): Buffer {
  let bits: number;
  if (isCA) {
    // keyCertSign (5) | cRLSign (6) → byte = 0x06, unused = 1
    bits = 0x06;
  } else {
    // digitalSignature (0) | keyEncipherment (2) → byte = 0xa0, unused = 5
    bits = 0xa0;
  }
  const unusedBits = isCA ? 1 : 5;
  const bitStringContent = Buffer.from([unusedBits, bits]);
  const bitString = derTlv(0x03, bitStringContent);
  const octetValue = derTlv(0x04, bitString);
  const parts: Buffer[] = [derOid(OID_KEY_USAGE)];
  if (critical) parts.push(derTlv(0x01, Buffer.from([0xff])));
  parts.push(octetValue);
  return derSeq(parts);
}

function buildSanExt(ips: string[]): Buffer {
  const names = ips.map((ip) => {
    const bytes = ip.split('.').map(Number);
    return derContextOctetString(7, Buffer.from(bytes));
  });
  const sanValue = derSeq(names);
  const octetValue = derTlv(0x04, sanValue);
  return derSeq([derOid(OID_SAN), octetValue]);
}

function buildExtensions(exts: Buffer[]): Buffer {
  return derContextExplicit(3, derSeq(exts));
}

// ---------------------------------------------------------------------------
// Certificate generation
// ---------------------------------------------------------------------------

function generateSerial(): Buffer {
  const bytes = crypto.randomBytes(16);
  // Ensure positive (clear high bit)
  bytes[0] &= 0x7f;
  // Ensure non-zero
  if (bytes[0] === 0) bytes[0] = 1;
  return bytes;
}

function buildTbs(options: {
  serial: Buffer;
  issuer: Buffer;
  subject: Buffer;
  validity: Buffer;
  publicKeyInfo: Buffer;
  extensions: Buffer;
}): Buffer {
  return derSeq([
    derContextExplicit(0, derInteger(2)), // v3
    derInteger(options.serial),
    buildAlgorithmIdentifier(),
    options.issuer,
    options.validity,
    options.subject,
    options.publicKeyInfo,
    options.extensions,
  ]);
}

function wrapCertificate(tbs: Buffer, signature: Buffer): Buffer {
  return derSeq([tbs, buildAlgorithmIdentifier(), derBitString(signature)]);
}

function toPem(tag: string, der: Buffer): string {
  const b64 = der.toString('base64');
  const lines: string[] = [];
  for (let i = 0; i < b64.length; i += 64) {
    lines.push(b64.slice(i, i + 64));
  }
  return `-----BEGIN ${tag}-----\n${lines.join('\n')}\n-----END ${tag}-----\n`;
}

function wrapAndSign(
  tbs: Buffer,
  signingKey: crypto.KeyObject,
  subjectKey: crypto.KeyObject,
): { cert: string; key: string } {
  const signature = crypto.sign('sha256', tbs, signingKey);
  return {
    cert: toPem('CERTIFICATE', wrapCertificate(tbs, signature)),
    key: subjectKey.export({ type: 'pkcs8', format: 'pem' }) as string,
  };
}

function buildCertTbs(options: {
  issuerCn: string;
  subjectCn: string;
  validityYears: number;
  publicKeyDer: Buffer;
  extensions: Buffer[];
}): Buffer {
  const now = new Date();
  const notAfter = new Date(now);
  notAfter.setUTCFullYear(notAfter.getUTCFullYear() + options.validityYears);

  return buildTbs({
    serial: generateSerial(),
    issuer: buildName(options.issuerCn),
    subject: buildName(options.subjectCn),
    validity: buildValidity(now, notAfter),
    publicKeyInfo: Buffer.from(options.publicKeyDer),
    extensions: buildExtensions(options.extensions),
  });
}

function generateCaCert(): { cert: string; key: string } {
  // Self-signed: same keypair for subject and signer
  const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });

  const tbs = buildCertTbs({
    issuerCn: 'ppg-ca',
    subjectCn: 'ppg-ca',
    validityYears: 10,
    publicKeyDer: publicKey.export({ type: 'spki', format: 'der' }),
    extensions: [
      buildBasicConstraintsExt(true, true),
      buildKeyUsageExt(true, true),
    ],
  });

  return wrapAndSign(tbs, privateKey, privateKey);
}

function generateServerCert(caKey: string, sans: string[]): { cert: string; key: string } {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });

  const tbs = buildCertTbs({
    issuerCn: 'ppg-ca',
    subjectCn: 'ppg-server',
    validityYears: 1,
    publicKeyDer: publicKey.export({ type: 'spki', format: 'der' }),
    extensions: [
      buildBasicConstraintsExt(false, false),
      buildKeyUsageExt(false, false),
      buildSanExt(sans),
    ],
  });

  return wrapAndSign(tbs, crypto.createPrivateKey(caKey), privateKey);
}

// ---------------------------------------------------------------------------
// LAN IP detection
// ---------------------------------------------------------------------------

export function getLanIps(): string[] {
  const interfaces = os.networkInterfaces();
  const ips = new Set<string>();
  ips.add('127.0.0.1');

  for (const infos of Object.values(interfaces)) {
    if (!infos) continue;
    for (const info of infos) {
      if (info.family === 'IPv4' && !info.internal) {
        ips.add(info.address);
      }
    }
  }

  return [...ips];
}

// ---------------------------------------------------------------------------
// Pairing URL
// ---------------------------------------------------------------------------

export function buildPairingUrl(params: {
  host: string;
  port: number;
  caFingerprint: string;
  token: string;
}): string {
  const q = new URLSearchParams({
    host: params.host,
    port: String(params.port),
    ca: params.caFingerprint,
    token: params.token,
  });
  return `ppg://connect?${q.toString()}`;
}

// ---------------------------------------------------------------------------
// File I/O and reuse logic
// ---------------------------------------------------------------------------

function loadTlsBundle(projectRoot: string): TlsBundle | null {
  const paths = [
    tlsCaKeyPath(projectRoot),
    tlsCaCertPath(projectRoot),
    tlsServerKeyPath(projectRoot),
    tlsServerCertPath(projectRoot),
  ];

  const contents: string[] = [];
  for (const p of paths) {
    try {
      contents.push(fs.readFileSync(p, 'utf8'));
    } catch {
      return null;
    }
  }

  const [caKey, caCert, serverKey, serverCert] = contents;

  try {
    const x509 = new crypto.X509Certificate(caCert);
    const serverX509 = new crypto.X509Certificate(serverCert);
    const fingerprint = x509.fingerprint256;
    const sanStr = serverX509.subjectAltName ?? '';
    const sans = [...sanStr.matchAll(/IP Address:(\d+\.\d+\.\d+\.\d+)/g)].map(
      (m) => m[1],
    );

    return { caCert, caKey, serverCert, serverKey, caFingerprint: fingerprint, sans };
  } catch {
    return null;
  }
}

function isCaValid(caCert: string, minDaysRemaining: number): boolean {
  try {
    const x509 = new crypto.X509Certificate(caCert);
    const notAfter = new Date(x509.validTo);
    const remaining = (notAfter.getTime() - Date.now()) / (1000 * 60 * 60 * 24);
    return remaining > minDaysRemaining;
  } catch {
    return false;
  }
}

function isServerCertValid(
  serverCert: string,
  requiredIps: string[],
  minDaysRemaining: number,
): boolean {
  try {
    const x509 = new crypto.X509Certificate(serverCert);
    const notAfter = new Date(x509.validTo);
    const remaining = (notAfter.getTime() - Date.now()) / (1000 * 60 * 60 * 24);
    if (remaining <= minDaysRemaining) return false;

    const sanStr = x509.subjectAltName ?? '';
    const certIps = new Set(
      [...sanStr.matchAll(/IP Address:(\d+\.\d+\.\d+\.\d+)/g)].map((m) => m[1]),
    );

    return requiredIps.every((ip) => certIps.has(ip));
  } catch {
    return false;
  }
}

function writePemFile(filePath: string, content: string): void {
  fs.writeFileSync(filePath, content, { mode: 0o600 });
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

export function ensureTls(projectRoot: string): TlsBundle {
  const dir = tlsDir(projectRoot);
  fs.mkdirSync(dir, { recursive: true });

  const lanIps = getLanIps();
  const existing = loadTlsBundle(projectRoot);

  if (existing) {
    // Check if everything is still valid
    const caOk = isCaValid(existing.caCert, 30);
    const serverOk = isServerCertValid(existing.serverCert, lanIps, 7);

    if (caOk && serverOk) {
      return existing;
    }

    // CA still valid — only regenerate server cert
    if (caOk) {
      const server = generateServerCert(existing.caKey, lanIps);
      writePemFile(tlsServerKeyPath(projectRoot), server.key);
      writePemFile(tlsServerCertPath(projectRoot), server.cert);

      const x509 = new crypto.X509Certificate(existing.caCert);
      return {
        caCert: existing.caCert,
        caKey: existing.caKey,
        serverCert: server.cert,
        serverKey: server.key,
        caFingerprint: x509.fingerprint256,
        sans: lanIps,
      };
    }
  }

  // Generate everything fresh
  const ca = generateCaCert();
  const server = generateServerCert(ca.key, lanIps);

  writePemFile(tlsCaKeyPath(projectRoot), ca.key);
  writePemFile(tlsCaCertPath(projectRoot), ca.cert);
  writePemFile(tlsServerKeyPath(projectRoot), server.key);
  writePemFile(tlsServerCertPath(projectRoot), server.cert);

  const x509 = new crypto.X509Certificate(ca.cert);

  return {
    caCert: ca.cert,
    caKey: ca.key,
    serverCert: server.cert,
    serverKey: server.key,
    caFingerprint: x509.fingerprint256,
    sans: lanIps,
  };
}
