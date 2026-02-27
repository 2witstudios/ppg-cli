import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
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

  async function readData(): Promise<AuthData> {
    try {
      const raw = await fs.readFile(filePath, 'utf-8');
      return JSON.parse(raw) as AuthData;
    } catch {
      return { tokens: [] };
    }
  }

  async function writeData(data: AuthData): Promise<void> {
    const dir = serveDir(projectRoot);
    await fs.mkdir(dir, { recursive: true });
    await fs.writeFile(filePath, JSON.stringify(data, null, 2), {
      mode: 0o600,
    });
  }

  return {
    async addToken(label: string): Promise<string> {
      const data = await readData();
      const existing = data.tokens.find((t) => t.label === label);
      if (existing) {
        throw new Error(`Token with label "${label}" already exists`);
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
      const incoming = hashToken(token);

      for (const entry of data.tokens) {
        const a = Buffer.from(incoming, 'hex');
        const b = Buffer.from(entry.hash, 'hex');
        if (a.length === b.length && crypto.timingSafeEqual(a, b)) {
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

export function createAuthHook(deps: AuthHookDeps) {
  const { store, rateLimiter } = deps;

  return async function authHook(
    request: { headers: Record<string, string | undefined>; ip: string },
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

    rateLimiter.reset(ip);
  };
}
