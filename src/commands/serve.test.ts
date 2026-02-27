import { describe, test, expect } from 'vitest';

import { buildPairingUrl, getLocalIp, verifyToken } from './serve.js';

describe('buildPairingUrl', () => {
  test('given valid params, should encode all fields into ppg:// URL', () => {
    const url = buildPairingUrl({
      host: '192.168.1.10',
      port: 7700,
      fingerprint: 'AA:BB:CC',
      token: 'test-token-123',
    });

    expect(url).toContain('ppg://connect');
    expect(url).toContain('host=192.168.1.10');
    expect(url).toContain('port=7700');
    expect(url).toContain('ca=AA%3ABB%3ACC');
    expect(url).toContain('token=test-token-123');
  });

  test('given special characters in token, should URL-encode them', () => {
    const url = buildPairingUrl({
      host: '10.0.0.1',
      port: 8080,
      fingerprint: 'DE:AD:BE:EF',
      token: 'a+b/c=d',
    });

    expect(url).toContain('token=a%2Bb%2Fc%3Dd');
  });
});

describe('getLocalIp', () => {
  test('should return a non-empty string', () => {
    const ip = getLocalIp();
    expect(ip).toBeTruthy();
    expect(typeof ip).toBe('string');
  });

  test('should return a valid IPv4 address', () => {
    const ip = getLocalIp();
    const ipv4Pattern = /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/;
    expect(ip).toMatch(ipv4Pattern);
  });
});

describe('verifyToken', () => {
  test('given matching tokens, should return true', () => {
    expect(verifyToken('correct-token', 'correct-token')).toBe(true);
  });

  test('given different tokens of same length, should return false', () => {
    expect(verifyToken('aaaa-bbbb-cccc', 'xxxx-yyyy-zzzz')).toBe(false);
  });

  test('given different length tokens, should return false', () => {
    expect(verifyToken('short', 'much-longer-token')).toBe(false);
  });

  test('given empty provided token, should return false', () => {
    expect(verifyToken('', 'expected-token')).toBe(false);
  });

  test('given both empty, should return true', () => {
    expect(verifyToken('', '')).toBe(true);
  });
});
