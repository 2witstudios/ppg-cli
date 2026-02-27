import { describe, test, expect, beforeEach, afterEach, vi } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';
import errorHandlerPlugin, {
  httpStatusForPpgError,
  type ErrorResponseBody,
} from './error-handler.js';
import { PpgError } from '../lib/errors.js';

describe('errorHandlerPlugin', () => {
  let app: FastifyInstance;

  beforeEach(async () => {
    app = Fastify({ logger: false });
    await app.register(errorHandlerPlugin);
  });

  afterEach(async () => {
    vi.unstubAllEnvs();
    await app.close();
  });

  test('given a WORKTREE_NOT_FOUND PpgError, should return 404 with its code', async () => {
    app.get('/ppg-error', () => {
      throw new PpgError('Worktree not found: wt-abc123', 'WORKTREE_NOT_FOUND');
    });
    await app.ready();

    const response = await app.inject({ method: 'GET', url: '/ppg-error' });
    const body = response.json<ErrorResponseBody>();

    expect(response.statusCode).toBe(404);
    expect(body.error.code).toBe('WORKTREE_NOT_FOUND');
    expect(body.error.message).toBe('Worktree not found: wt-abc123');
  });

  test('given an AGENT_NOT_FOUND PpgError, should return 404', async () => {
    app.get('/ppg-404', () => {
      throw new PpgError('Agent not found: ag-abc', 'AGENT_NOT_FOUND');
    });
    await app.ready();

    const response = await app.inject({ method: 'GET', url: '/ppg-404' });

    expect(response.statusCode).toBe(404);
    expect(response.json<ErrorResponseBody>().error.code).toBe('AGENT_NOT_FOUND');
  });

  test('given a MANIFEST_LOCK PpgError, should return 409', async () => {
    app.get('/ppg-lock', () => {
      throw new PpgError('Could not acquire lock', 'MANIFEST_LOCK');
    });
    await app.ready();

    const response = await app.inject({ method: 'GET', url: '/ppg-lock' });

    expect(response.statusCode).toBe(409);
  });

  test('given an unknown PpgError code, should default to 400', async () => {
    app.get('/ppg-unknown', () => {
      throw new PpgError('Something odd', 'UNKNOWN_CODE');
    });
    await app.ready();

    const response = await app.inject({ method: 'GET', url: '/ppg-unknown' });

    expect(response.statusCode).toBe(400);
  });

  test('given a validation error, should return 400 with VALIDATION_ERROR code', async () => {
    app.get('/validation', () => {
      const err = new Error('body/name must be string') as Error & {
        validation: unknown;
        statusCode: number;
      };
      err.validation = [{ message: 'must be string' }];
      err.statusCode = 400;
      throw err;
    });
    await app.ready();

    const response = await app.inject({ method: 'GET', url: '/validation' });
    const body = response.json<ErrorResponseBody>();

    expect(response.statusCode).toBe(400);
    expect(body.error.code).toBe('VALIDATION_ERROR');
    expect(body.error.message).toBe('body/name must be string');
  });

  test('given an unhandled error in production, should not leak details', async () => {
    vi.stubEnv('NODE_ENV', 'production');

    app.get('/unexpected', () => {
      throw new Error('secret database connection string leaked');
    });
    await app.ready();

    const response = await app.inject({ method: 'GET', url: '/unexpected' });
    const body = response.json<ErrorResponseBody>();

    expect(response.statusCode).toBe(500);
    expect(body.error.code).toBe('INTERNAL_ERROR');
    expect(body.error.message).toBe('Internal server error');
    expect(JSON.stringify(body)).not.toContain('secret');
  });

  test('given an unhandled error in development, should include error message', async () => {
    vi.stubEnv('NODE_ENV', 'development');

    app.get('/dev-error', () => {
      throw new Error('something broke');
    });
    await app.ready();

    const response = await app.inject({ method: 'GET', url: '/dev-error' });
    const body = response.json<ErrorResponseBody>();

    expect(response.statusCode).toBe(500);
    expect(body.error.code).toBe('INTERNAL_ERROR');
    expect(body.error.message).toBe('something broke');
  });

  test('given an unhandled error with statusCode, should preserve it', async () => {
    app.get('/custom-status', () => {
      const err = new Error('service unavailable') as Error & {
        statusCode: number;
      };
      err.statusCode = 503;
      throw err;
    });
    await app.ready();

    const response = await app.inject({ method: 'GET', url: '/custom-status' });

    expect(response.statusCode).toBe(503);
    expect(response.json<ErrorResponseBody>().error.code).toBe('INTERNAL_ERROR');
  });

  test('given an error with statusCode < 400, should default to 500', async () => {
    app.get('/low-status', () => {
      const err = new Error('weird status') as Error & { statusCode: number };
      err.statusCode = 200;
      throw err;
    });
    await app.ready();

    const response = await app.inject({ method: 'GET', url: '/low-status' });

    expect(response.statusCode).toBe(500);
  });

  test('given an error response, should return application/json content-type', async () => {
    app.get('/json-check', () => {
      throw new Error('test');
    });
    await app.ready();

    const response = await app.inject({ method: 'GET', url: '/json-check' });

    expect(response.headers['content-type']).toContain('application/json');
  });

  test('given an async route that rejects, should catch and format the error', async () => {
    app.get('/async-error', async () => {
      throw new PpgError('Not initialized', 'NOT_INITIALIZED');
    });
    await app.ready();

    const response = await app.inject({ method: 'GET', url: '/async-error' });
    const body = response.json<ErrorResponseBody>();

    expect(response.statusCode).toBe(400);
    expect(body.error.code).toBe('NOT_INITIALIZED');
  });
});

describe('httpStatusForPpgError', () => {
  test('given a known code, should return the mapped HTTP status', () => {
    expect(httpStatusForPpgError('WORKTREE_NOT_FOUND')).toBe(404);
    expect(httpStatusForPpgError('AGENT_NOT_FOUND')).toBe(404);
    expect(httpStatusForPpgError('MANIFEST_LOCK')).toBe(409);
    expect(httpStatusForPpgError('WAIT_TIMEOUT')).toBe(504);
    expect(httpStatusForPpgError('TMUX_NOT_FOUND')).toBe(500);
  });

  test('given an unknown code, should return 400', () => {
    expect(httpStatusForPpgError('MADE_UP_CODE')).toBe(400);
  });
});
