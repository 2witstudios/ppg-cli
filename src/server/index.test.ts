import { describe, test, expect, vi, afterEach } from 'vitest';
import os from 'node:os';
import { detectLanAddress, timingSafeTokenMatch } from './index.js';

describe('detectLanAddress', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  test('given interfaces with a non-internal IPv4 address, should return it', () => {
    vi.spyOn(os, 'networkInterfaces').mockReturnValue({
      lo0: [
        { address: '127.0.0.1', family: 'IPv4', internal: true, netmask: '255.0.0.0', mac: '00:00:00:00:00:00', cidr: '127.0.0.1/8' },
      ],
      en0: [
        { address: 'fe80::1', family: 'IPv6', internal: false, netmask: 'ffff:ffff:ffff:ffff::', mac: 'aa:bb:cc:dd:ee:ff', cidr: 'fe80::1/64', scopeid: 1 },
        { address: '192.168.1.42', family: 'IPv4', internal: false, netmask: '255.255.255.0', mac: 'aa:bb:cc:dd:ee:ff', cidr: '192.168.1.42/24' },
      ],
    });
    expect(detectLanAddress()).toBe('192.168.1.42');
  });

  test('given only internal interfaces, should return undefined', () => {
    vi.spyOn(os, 'networkInterfaces').mockReturnValue({
      lo0: [
        { address: '127.0.0.1', family: 'IPv4', internal: true, netmask: '255.0.0.0', mac: '00:00:00:00:00:00', cidr: '127.0.0.1/8' },
      ],
    });
    expect(detectLanAddress()).toBeUndefined();
  });

  test('given empty interfaces, should return undefined', () => {
    vi.spyOn(os, 'networkInterfaces').mockReturnValue({});
    expect(detectLanAddress()).toBeUndefined();
  });
});

describe('timingSafeTokenMatch', () => {
  const token = 'my-secret-token';

  test('given matching bearer token, should return true', () => {
    expect(timingSafeTokenMatch(`Bearer ${token}`, token)).toBe(true);
  });

  test('given wrong token, should return false', () => {
    expect(timingSafeTokenMatch('Bearer wrong-token!', token)).toBe(false);
  });

  test('given missing header, should return false', () => {
    expect(timingSafeTokenMatch(undefined, token)).toBe(false);
  });

  test('given empty header, should return false', () => {
    expect(timingSafeTokenMatch('', token)).toBe(false);
  });

  test('given header with different length, should return false', () => {
    expect(timingSafeTokenMatch('Bearer short', token)).toBe(false);
  });

  test('given header with same char length but different byte length, should return false', () => {
    const unicodeHeader = `Bearer ${'é'.repeat(token.length)}`;
    expect(() => timingSafeTokenMatch(unicodeHeader, token)).not.toThrow();
    expect(timingSafeTokenMatch(unicodeHeader, token)).toBe(false);
  });

  test('given raw token without Bearer prefix, should return false', () => {
    const padded = token.padEnd(`Bearer ${token}`.length, 'x');
    expect(timingSafeTokenMatch(padded, token)).toBe(false);
  });
});
