import { describe, test, expect, beforeEach, afterEach, vi } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';
import errorHandlerPlugin, { type ErrorResponseBody } from './error-handler.js';
import { PpgError } from '../lib/errors.js';

describe('errorHandlerPlugin', () => {
  let app: FastifyInstance;

  beforeEach(async () => {
    app = Fastify({ logger: false });
    await app.register(errorHandlerPlugin);
  });

  afterEach(async () => {
    await app.close();
  });

  test('given a PpgError, should return its code and message', async () => {
    app.get('/ppg-error', () => {
      throw new PpgError('Worktree not found: wt-abc123', 'WORKTREE_NOT_FOUND');
    });

    const response = await app.inject({ method: 'GET', url: '/ppg-error' });
    const body = response.json<ErrorResponseBody>();

    expect(response.statusCode).toBe(400);
    expect(body.error.code).toBe('WORKTREE_NOT_FOUND');
    expect(body.error.message).toBe('Worktree not found: wt-abc123');
  });

  test('given a PpgError with exitCode >= 400, should use exitCode as status', async () => {
    app.get('/ppg-404', () => {
      throw new PpgError('Not found', 'AGENT_NOT_FOUND', 404);
    });

    const response = await app.inject({ method: 'GET', url: '/ppg-404' });

    expect(response.statusCode).toBe(404);
    expect(response.json<ErrorResponseBody>().error.code).toBe('AGENT_NOT_FOUND');
  });

  test('given a PpgError with exitCode < 400, should default to 400', async () => {
    app.get('/ppg-low-exit', () => {
      throw new PpgError('Bad exit', 'SOME_ERROR', 1);
    });

    const response = await app.inject({ method: 'GET', url: '/ppg-low-exit' });

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

    const response = await app.inject({ method: 'GET', url: '/validation' });
    const body = response.json<ErrorResponseBody>();

    expect(response.statusCode).toBe(400);
    expect(body.error.code).toBe('VALIDATION_ERROR');
    expect(body.error.message).toBe('body/name must be string');
  });

  test('given an unhandled error in production, should not leak details', async () => {
    const original = process.env['NODE_ENV'];
    process.env['NODE_ENV'] = 'production';

    app.get('/unexpected', () => {
      throw new Error('secret database connection string leaked');
    });

    const response = await app.inject({ method: 'GET', url: '/unexpected' });
    const body = response.json<ErrorResponseBody>();

    expect(response.statusCode).toBe(500);
    expect(body.error.code).toBe('INTERNAL_ERROR');
    expect(body.error.message).toBe('Internal server error');
    expect(JSON.stringify(body)).not.toContain('secret');

    process.env['NODE_ENV'] = original;
  });

  test('given an unhandled error in development, should include error message', async () => {
    const original = process.env['NODE_ENV'];
    delete process.env['NODE_ENV'];

    app.get('/dev-error', () => {
      throw new Error('something broke');
    });

    const response = await app.inject({ method: 'GET', url: '/dev-error' });
    const body = response.json<ErrorResponseBody>();

    expect(response.statusCode).toBe(500);
    expect(body.error.code).toBe('INTERNAL_ERROR');
    expect(body.error.message).toBe('something broke');

    process.env['NODE_ENV'] = original;
  });

  test('given an unhandled error with statusCode, should preserve it', async () => {
    app.get('/custom-status', () => {
      const err = new Error('service unavailable') as Error & {
        statusCode: number;
      };
      err.statusCode = 503;
      throw err;
    });

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

    const response = await app.inject({ method: 'GET', url: '/low-status' });

    expect(response.statusCode).toBe(500);
  });

  test('should return valid JSON content-type', async () => {
    app.get('/json-check', () => {
      throw new Error('test');
    });

    const response = await app.inject({ method: 'GET', url: '/json-check' });

    expect(response.headers['content-type']).toContain('application/json');
  });
});
