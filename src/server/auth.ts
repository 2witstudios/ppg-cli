import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import { getWriteFileAtomic } from '../lib/cjs-compat.js';
import { AuthCorruptError, DuplicateTokenError } from '../lib/errors.js';
import { authPath, serveDir } from '../lib/paths.js';

// --- Types ---

export interface TokenEntry {
  label: string;
  hash: string;
  createdAt: string;
  lastUsedAt: string | null;
}

export interface AuthData {
  tokens: TokenEntry[];
}

interface RateLimitEntry {
  failures: number;
  windowStart: number;
}

// --- Constants ---

const RATE_LIMIT_MAX_FAILURES = 5;
const RATE_LIMIT_WINDOW_MS = 5 * 60 * 1000; // 5 minutes
const RATE_LIMIT_MAX_ENTRIES = 10_000;

// --- Token Generation & Hashing ---

export function generateToken(): string {
  const bytes = crypto.randomBytes(24);
  return `tk_${bytes.toString('base64url')}`;
}

export function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}

// --- Rate Limiter ---

export interface RateLimiter {
  check(ip: string): boolean;
  record(ip: string): void;
  reset(ip: string): void;
}

export function createRateLimiter(
  now: () => number = Date.now,
): RateLimiter {
  const entries = new Map<string, RateLimitEntry>();

  function prune(): void {
    if (entries.size <= RATE_LIMIT_MAX_ENTRIES) return;
    const currentTime = now();
    for (const [ip, entry] of entries) {
      if (currentTime - entry.windowStart >= RATE_LIMIT_WINDOW_MS) {
        entries.delete(ip);
      }
    }
  }

  return {
    check(ip: string): boolean {
      const entry = entries.get(ip);
      if (!entry) return true;

      if (now() - entry.windowStart >= RATE_LIMIT_WINDOW_MS) {
        entries.delete(ip);
        return true;
      }

      return entry.failures < RATE_LIMIT_MAX_FAILURES;
    },

    record(ip: string): void {
      const entry = entries.get(ip);
      const currentTime = now();

      if (!entry || currentTime - entry.windowStart >= RATE_LIMIT_WINDOW_MS) {
        entries.set(ip, { failures: 1, windowStart: currentTime });
        prune();
        return;
      }

      entry.failures += 1;
    },

    reset(ip: string): void {
      entries.delete(ip);
    },
  };
}

// --- Auth Store ---

export interface AuthStore {
  addToken(label: string): Promise<string>;
  validateToken(token: string): Promise<TokenEntry | null>;
  revokeToken(label: string): Promise<boolean>;
  listTokens(): Promise<TokenEntry[]>;
}

export async function createAuthStore(projectRoot: string): Promise<AuthStore> {
  const filePath = authPath(projectRoot);
  let cache: AuthData | null = null;

  async function readData(): Promise<AuthData> {
    if (cache) return cache;
    try {
      const raw = await fs.readFile(filePath, 'utf-8');
      cache = JSON.parse(raw) as AuthData;
      return cache;
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
        cache = { tokens: [] };
        return cache;
      }
      throw new AuthCorruptError(filePath);
    }
  }

  async function writeData(data: AuthData): Promise<void> {
    const dir = serveDir(projectRoot);
    await fs.mkdir(dir, { recursive: true });
    const writeFileAtomic = await getWriteFileAtomic();
    await writeFileAtomic(filePath, JSON.stringify(data, null, 2), {
      mode: 0o600,
    });
    cache = data;
  }

  return {
    async addToken(label: string): Promise<string> {
      const data = await readData();
      const existing = data.tokens.find((t) => t.label === label);
      if (existing) {
        throw new DuplicateTokenError(label);
      }

      const token = generateToken();
      const entry: TokenEntry = {
        label,
        hash: hashToken(token),
        createdAt: new Date().toISOString(),
        lastUsedAt: null,
      };
      data.tokens.push(entry);
      await writeData(data);
      return token;
    },

    async validateToken(token: string): Promise<TokenEntry | null> {
      const data = await readData();
      const incomingBuf = Buffer.from(hashToken(token), 'hex');

      for (const entry of data.tokens) {
        const storedBuf = Buffer.from(entry.hash, 'hex');
        if (incomingBuf.length === storedBuf.length && crypto.timingSafeEqual(incomingBuf, storedBuf)) {
          entry.lastUsedAt = new Date().toISOString();
          await writeData(data);
          return entry;
        }
      }

      return null;
    },

    async revokeToken(label: string): Promise<boolean> {
      const data = await readData();
      const idx = data.tokens.findIndex((t) => t.label === label);
      if (idx === -1) return false;
      data.tokens.splice(idx, 1);
      await writeData(data);
      return true;
    },

    async listTokens(): Promise<TokenEntry[]> {
      const data = await readData();
      return data.tokens;
    },
  };
}

// --- Fastify Auth Hook ---

export interface AuthHookDeps {
  store: AuthStore;
  rateLimiter: RateLimiter;
}

export interface AuthenticatedRequest {
  headers: Record<string, string | undefined>;
  ip: string;
  tokenEntry?: TokenEntry;
}

export function createAuthHook(deps: AuthHookDeps) {
  const { store, rateLimiter } = deps;

  return async function authHook(
    request: AuthenticatedRequest,
    reply: { code(statusCode: number): { send(body: unknown): void } },
  ): Promise<void> {
    const ip = request.ip;

    if (!rateLimiter.check(ip)) {
      reply.code(429).send({ error: 'Too many failed attempts. Try again later.' });
      return;
    }

    const authHeader = request.headers['authorization'];
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      rateLimiter.record(ip);
      reply.code(401).send({ error: 'Missing or malformed Authorization header' });
      return;
    }

    const token = authHeader.slice(7);
    const entry = await store.validateToken(token);

    if (!entry) {
      rateLimiter.record(ip);
      reply.code(401).send({ error: 'Invalid token' });
      return;
    }

    request.tokenEntry = entry;
    rateLimiter.reset(ip);
  };
}
