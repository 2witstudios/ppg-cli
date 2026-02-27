import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { DuplicateTokenError } from '../lib/errors.js';
import { authPath } from '../lib/paths.js';
import {
  type AuthStore,
  type AuthenticatedRequest,
  type RateLimiter,
  createAuthHook,
  createAuthStore,
  createRateLimiter,
  generateToken,
  hashToken,
} from './auth.js';

// --- Test Helpers ---

function makeReply() {
  let sentStatus: number | null = null;
  let sentBody: unknown = null;
  return {
    reply: {
      code(status: number) {
        sentStatus = status;
        return {
          send(body: unknown) {
            sentBody = body;
          },
        };
      },
    },
    status: () => sentStatus,
    body: () => sentBody,
  };
}

function makeRequest(overrides: Partial<{ headers: Record<string, string | string[] | undefined>; ip: string }> = {}): AuthenticatedRequest {
  return {
    headers: {},
    ip: '127.0.0.1',
    ...overrides,
  };
}

// --- Token Generation ---

describe('generateToken', () => {
  test('returns string with tk_ prefix', () => {
    const token = generateToken();
    expect(token.startsWith('tk_')).toBe(true);
  });

  test('body is valid base64url (32 chars from 24 bytes)', () => {
    const token = generateToken();
    const body = token.slice(3);
    expect(body).toMatch(/^[A-Za-z0-9_-]+$/);
    expect(body.length).toBe(32);
  });

  test('generates unique tokens', () => {
    const tokens = new Set(Array.from({ length: 50 }, () => generateToken()));
    expect(tokens.size).toBe(50);
  });
});

// --- Token Hashing ---

describe('hashToken', () => {
  test('returns a 64-char hex SHA-256 digest', () => {
    const hash = hashToken('tk_test');
    expect(hash).toMatch(/^[a-f0-9]{64}$/);
  });

  test('same input produces same hash', () => {
    const a = hashToken('tk_abc123');
    const b = hashToken('tk_abc123');
    expect(a).toBe(b);
  });

  test('different inputs produce different hashes', () => {
    const a = hashToken('tk_abc');
    const b = hashToken('tk_xyz');
    expect(a).not.toBe(b);
  });
});

// --- Rate Limiter ---

describe('createRateLimiter', () => {
  let clock: number;
  let limiter: RateLimiter;

  beforeEach(() => {
    clock = 1000000;
    limiter = createRateLimiter(() => clock);
  });

  test('allows first request from new IP', () => {
    expect(limiter.check('1.2.3.4')).toBe(true);
  });

  test('allows up to 5 failures', () => {
    const ip = '1.2.3.4';
    for (let i = 0; i < 4; i++) {
      limiter.record(ip);
      expect(limiter.check(ip)).toBe(true);
    }
    limiter.record(ip);
    expect(limiter.check(ip)).toBe(false);
  });

  test('blocks after 5 failures within window', () => {
    const ip = '10.0.0.1';
    for (let i = 0; i < 5; i++) limiter.record(ip);
    expect(limiter.check(ip)).toBe(false);
  });

  test('resets after window expires', () => {
    const ip = '10.0.0.2';
    for (let i = 0; i < 5; i++) limiter.record(ip);
    expect(limiter.check(ip)).toBe(false);

    clock += 5 * 60 * 1000; // advance 5 minutes
    expect(limiter.check(ip)).toBe(true);
  });

  test('starts new window after expiry', () => {
    const ip = '10.0.0.3';
    for (let i = 0; i < 5; i++) limiter.record(ip);
    expect(limiter.check(ip)).toBe(false);

    clock += 5 * 60 * 1000;
    limiter.record(ip); // new window, failure count = 1
    expect(limiter.check(ip)).toBe(true);
  });

  test('tracks IPs independently', () => {
    for (let i = 0; i < 5; i++) limiter.record('a');
    expect(limiter.check('a')).toBe(false);
    expect(limiter.check('b')).toBe(true);
  });

  test('reset clears failure count for IP', () => {
    const ip = '10.0.0.4';
    for (let i = 0; i < 5; i++) limiter.record(ip);
    expect(limiter.check(ip)).toBe(false);
    limiter.reset(ip);
    expect(limiter.check(ip)).toBe(true);
  });

  test('prunes stale entries when map exceeds max size', () => {
    // Fill with 10001 stale entries
    for (let i = 0; i <= 10_000; i++) {
      limiter.record(`stale-${i}`);
    }
    // Advance past the window so all are stale
    clock += 5 * 60 * 1000;
    // One more record triggers prune
    limiter.record('fresh');
    // The fresh one should be tracked; stale ones should allow through
    expect(limiter.check('stale-0')).toBe(true);
    expect(limiter.check('fresh')).toBe(true);
  });

  test('evicts oldest entries when max size is exceeded without stale IPs', () => {
    for (let i = 0; i <= 10_000; i++) {
      const ip = `ip-${i}`;
      for (let j = 0; j < 5; j++) limiter.record(ip);
    }

    // Oldest entry should be evicted once capacity is exceeded.
    expect(limiter.check('ip-0')).toBe(true);
    expect(limiter.check('ip-10')).toBe(false);
    expect(limiter.check('ip-10000')).toBe(false);
  });
});

// --- Auth Store ---

describe('createAuthStore', () => {
  let tmpDir: string;
  let store: AuthStore;

  beforeEach(async () => {
    tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'ppg-auth-'));
    store = await createAuthStore(tmpDir);
  });

  afterEach(async () => {
    await fs.rm(tmpDir, { recursive: true, force: true });
  });

  describe('addToken', () => {
    test('returns a token with tk_ prefix', async () => {
      const token = await store.addToken('iphone');
      expect(token.startsWith('tk_')).toBe(true);
    });

    test('stores hash, not plaintext', async () => {
      const token = await store.addToken('iphone');
      const raw = await fs.readFile(authPath(tmpDir), 'utf-8');
      const data = JSON.parse(raw);
      expect(data.tokens[0].hash).toBe(hashToken(token));
      expect(raw).not.toContain(token);
    });

    test('rejects duplicate labels with DuplicateTokenError', async () => {
      await store.addToken('ipad');
      await expect(store.addToken('ipad')).rejects.toThrow(DuplicateTokenError);
      await expect(store.addToken('ipad')).rejects.toThrow(
        'Token with label "ipad" already exists',
      );
    });

    test('supports multiple tokens with different labels', async () => {
      await store.addToken('iphone');
      await store.addToken('ipad');
      await store.addToken('macbook');
      const tokens = await store.listTokens();
      expect(tokens.length).toBe(3);
    });

    test('sets createdAt and null lastUsedAt', async () => {
      await store.addToken('device');
      const tokens = await store.listTokens();
      expect(tokens[0].createdAt).toBeTruthy();
      expect(tokens[0].lastUsedAt).toBeNull();
    });
  });

  describe('validateToken', () => {
    test('validates correct token', async () => {
      const token = await store.addToken('iphone');
      const entry = await store.validateToken(token);
      expect(entry).not.toBeNull();
      expect(entry!.label).toBe('iphone');
    });

    test('rejects invalid token', async () => {
      await store.addToken('iphone');
      const entry = await store.validateToken('tk_wrong');
      expect(entry).toBeNull();
    });

    test('rejects empty token', async () => {
      await store.addToken('iphone');
      const entry = await store.validateToken('');
      expect(entry).toBeNull();
    });

    test('updates lastUsedAt on successful validation', async () => {
      const token = await store.addToken('iphone');
      const before = await store.listTokens();
      expect(before[0].lastUsedAt).toBeNull();

      await store.validateToken(token);
      const after = await store.listTokens();
      expect(after[0].lastUsedAt).not.toBeNull();
    });

    test('returns defensive copy of token entry', async () => {
      const token = await store.addToken('iphone');
      const entry = await store.validateToken(token);
      expect(entry).not.toBeNull();
      entry!.label = 'tampered';

      const tokens = await store.listTokens();
      expect(tokens[0].label).toBe('iphone');
    });

    test('uses timing-safe comparison', async () => {
      const spy = vi.spyOn(crypto, 'timingSafeEqual');
      const token = await store.addToken('iphone');
      await store.validateToken(token);
      expect(spy).toHaveBeenCalled();
      spy.mockRestore();
    });

    test('validates correct token among multiple', async () => {
      const token1 = await store.addToken('iphone');
      await store.addToken('ipad');
      const token3 = await store.addToken('macbook');

      const entry1 = await store.validateToken(token1);
      expect(entry1!.label).toBe('iphone');

      const entry3 = await store.validateToken(token3);
      expect(entry3!.label).toBe('macbook');
    });
  });

  describe('revokeToken', () => {
    test('removes token by label', async () => {
      await store.addToken('iphone');
      const removed = await store.revokeToken('iphone');
      expect(removed).toBe(true);
      const tokens = await store.listTokens();
      expect(tokens.length).toBe(0);
    });

    test('returns false for unknown label', async () => {
      const removed = await store.revokeToken('nonexistent');
      expect(removed).toBe(false);
    });

    test('revoked token no longer validates', async () => {
      const token = await store.addToken('iphone');
      await store.revokeToken('iphone');
      const entry = await store.validateToken(token);
      expect(entry).toBeNull();
    });

    test('does not affect other tokens', async () => {
      const token1 = await store.addToken('iphone');
      await store.addToken('ipad');
      await store.revokeToken('ipad');

      const entry = await store.validateToken(token1);
      expect(entry!.label).toBe('iphone');
      const tokens = await store.listTokens();
      expect(tokens.length).toBe(1);
    });
  });

  describe('listTokens', () => {
    test('returns empty array when no tokens', async () => {
      const tokens = await store.listTokens();
      expect(tokens).toEqual([]);
    });

    test('returns all token entries', async () => {
      await store.addToken('a');
      await store.addToken('b');
      const tokens = await store.listTokens();
      expect(tokens.map((t) => t.label)).toEqual(['a', 'b']);
    });

    test('returns defensive copies', async () => {
      await store.addToken('a');
      const tokens = await store.listTokens();
      tokens[0].label = 'tampered';

      const fresh = await store.listTokens();
      expect(fresh[0].label).toBe('a');
    });
  });

  describe('persistence', () => {
    test('auth.json has 0o600 permissions', async () => {
      await store.addToken('iphone');
      const stat = await fs.stat(authPath(tmpDir));
      const mode = stat.mode & 0o777;
      expect(mode).toBe(0o600);
    });

    test('survives store recreation', async () => {
      const token = await store.addToken('iphone');
      const store2 = await createAuthStore(tmpDir);
      const entry = await store2.validateToken(token);
      expect(entry!.label).toBe('iphone');
    });

    test('throws AuthCorruptError on corrupt auth.json', async () => {
      await store.addToken('iphone');
      await fs.writeFile(authPath(tmpDir), '{{{invalid json');
      const store2 = await createAuthStore(tmpDir);
      await expect(store2.listTokens()).rejects.toThrow('Auth data is corrupt');
    });

    test('throws AuthCorruptError on invalid auth.json structure', async () => {
      await fs.mkdir(path.dirname(authPath(tmpDir)), { recursive: true });
      await fs.writeFile(
        authPath(tmpDir),
        JSON.stringify({ tokens: [{ label: 'incomplete' }] }),
      );
      const store2 = await createAuthStore(tmpDir);
      await expect(store2.listTokens()).rejects.toThrow('Auth data is corrupt');
    });
  });
});

// --- Fastify Auth Hook ---

describe('createAuthHook', () => {
  let store: AuthStore;
  let limiter: RateLimiter;
  let hook: ReturnType<typeof createAuthHook>;
  let tmpDir: string;
  let token: string;

  beforeEach(async () => {
    tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'ppg-auth-hook-'));
    store = await createAuthStore(tmpDir);
    limiter = createRateLimiter();
    hook = createAuthHook({ store, rateLimiter: limiter });
    token = await store.addToken('test-device');
  });

  afterEach(async () => {
    await fs.rm(tmpDir, { recursive: true, force: true });
  });

  test('passes with valid Bearer token', async () => {
    const { reply, status } = makeReply();
    await hook(
      makeRequest({ headers: { authorization: `Bearer ${token}` } }),
      reply,
    );
    expect(status()).toBeNull();
  });

  test('attaches tokenEntry to request on success', async () => {
    const { reply } = makeReply();
    const request = makeRequest({ headers: { authorization: `Bearer ${token}` } });
    await hook(request, reply);
    expect(request.tokenEntry).toBeDefined();
    expect(request.tokenEntry!.label).toBe('test-device');
  });

  test('rejects missing Authorization header', async () => {
    const { reply, status, body } = makeReply();
    await hook(makeRequest(), reply);
    expect(status()).toBe(401);
    expect(body()).toEqual({ error: 'Missing or malformed Authorization header' });
  });

  test('rejects non-Bearer scheme', async () => {
    const { reply, status } = makeReply();
    await hook(
      makeRequest({ headers: { authorization: `Basic ${token}` } }),
      reply,
    );
    expect(status()).toBe(401);
  });

  test('rejects invalid token', async () => {
    const { reply, status, body } = makeReply();
    await hook(
      makeRequest({ headers: { authorization: 'Bearer tk_invalid' } }),
      reply,
    );
    expect(status()).toBe(401);
    expect(body()).toEqual({ error: 'Invalid token' });
  });

  test('returns 429 when rate limited', async () => {
    for (let i = 0; i < 5; i++) {
      limiter.record('127.0.0.1');
    }
    const { reply, status, body } = makeReply();
    await hook(
      makeRequest({ headers: { authorization: `Bearer ${token}` } }),
      reply,
    );
    expect(status()).toBe(429);
    expect(body()).toEqual({ error: 'Too many failed attempts. Try again later.' });
  });

  test('records failure on missing header', async () => {
    for (let i = 0; i < 5; i++) {
      await hook(makeRequest(), makeReply().reply);
    }
    const { reply, status } = makeReply();
    await hook(makeRequest(), reply);
    expect(status()).toBe(429);
  });

  test('records failure on invalid token', async () => {
    for (let i = 0; i < 5; i++) {
      await hook(
        makeRequest({ headers: { authorization: 'Bearer tk_bad' } }),
        makeReply().reply,
      );
    }
    const { reply, status } = makeReply();
    await hook(
      makeRequest({ headers: { authorization: `Bearer ${token}` } }),
      reply,
    );
    expect(status()).toBe(429);
  });

  test('resets rate limit on successful auth', async () => {
    for (let i = 0; i < 4; i++) {
      await hook(
        makeRequest({ headers: { authorization: 'Bearer tk_bad' } }),
        makeReply().reply,
      );
    }
    // Successful auth should reset
    await hook(
      makeRequest({ headers: { authorization: `Bearer ${token}` } }),
      makeReply().reply,
    );
    // Should not be rate limited now
    const { reply, status } = makeReply();
    await hook(
      makeRequest({ headers: { authorization: 'Bearer tk_bad' } }),
      reply,
    );
    expect(status()).toBe(401); // not 429
  });

  test('rate limits per IP independently', async () => {
    for (let i = 0; i < 5; i++) {
      await hook(
        makeRequest({ ip: '10.0.0.1', headers: { authorization: 'Bearer tk_bad' } }),
        makeReply().reply,
      );
    }
    // Different IP should still work
    const { reply, status } = makeReply();
    await hook(
      makeRequest({ ip: '10.0.0.2', headers: { authorization: `Bearer ${token}` } }),
      reply,
    );
    expect(status()).toBeNull();
  });

  test('returns 503 when token validation throws', async () => {
    const brokenStore: AuthStore = {
      addToken: async () => 'tk_unused',
      validateToken: async () => {
        throw new Error('disk error');
      },
      revokeToken: async () => false,
      listTokens: async () => [],
    };
    const brokenHook = createAuthHook({
      store: brokenStore,
      rateLimiter: createRateLimiter(),
    });
    const { reply, status, body } = makeReply();
    await brokenHook(
      makeRequest({ headers: { authorization: 'Bearer tk_any' } }),
      reply,
    );
    expect(status()).toBe(503);
    expect(body()).toEqual({ error: 'Authentication unavailable' });
  });
});
