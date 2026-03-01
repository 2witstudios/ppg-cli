import { describe, expect, test, vi } from 'vitest';
import {
  AgentNotFoundError,
  MergeFailedError,
  ManifestLockError,
  NotGitRepoError,
  NotInitializedError,
  PpgError,
  TmuxNotFoundError,
  WorktreeNotFoundError,
  GhNotFoundError,
  UnmergedWorkError,
} from '../lib/errors.js';
import type { LogFn } from './error-handler.js';
import {
  buildErrorResponse,
  errorHandler,
  getHttpStatus,
  registerErrorHandler,
} from './error-handler.js';

describe('getHttpStatus', () => {
  test.each([
    ['INVALID_ARGS', 400],
    ['NO_SESSION_ID', 400],
    ['NOT_GIT_REPO', 400],
    ['NOT_INITIALIZED', 409],
    ['MANIFEST_LOCK', 409],
    ['AGENTS_RUNNING', 409],
    ['MERGE_FAILED', 409],
    ['UNMERGED_WORK', 409],
    ['WORKTREE_NOT_FOUND', 404],
    ['AGENT_NOT_FOUND', 404],
    ['PANE_NOT_FOUND', 404],
    ['NO_TMUX_WINDOW', 404],
    ['TARGET_NOT_FOUND', 404],
    ['WAIT_TIMEOUT', 408],
    ['AGENTS_FAILED', 500],
    ['TMUX_NOT_FOUND', 500],
    ['GH_NOT_FOUND', 500],
    ['DOWNLOAD_FAILED', 502],
    ['INSTALL_FAILED', 500],
  ])('maps %s → %d', (code, expected) => {
    expect(getHttpStatus(code)).toBe(expected);
  });

  test('returns 500 for unknown code', () => {
    expect(getHttpStatus('SOME_UNKNOWN_CODE')).toBe(500);
  });
});

describe('buildErrorResponse', () => {
  test.each<[string, PpgError, number, string]>([
    ['TmuxNotFoundError', new TmuxNotFoundError(), 500, 'TMUX_NOT_FOUND'],
    ['NotGitRepoError', new NotGitRepoError('/tmp'), 400, 'NOT_GIT_REPO'],
    ['NotInitializedError', new NotInitializedError('/tmp'), 409, 'NOT_INITIALIZED'],
    ['ManifestLockError', new ManifestLockError(), 409, 'MANIFEST_LOCK'],
    ['WorktreeNotFoundError', new WorktreeNotFoundError('wt-x'), 404, 'WORKTREE_NOT_FOUND'],
    ['AgentNotFoundError', new AgentNotFoundError('ag-y'), 404, 'AGENT_NOT_FOUND'],
    ['MergeFailedError', new MergeFailedError('conflict'), 409, 'MERGE_FAILED'],
    ['GhNotFoundError', new GhNotFoundError(), 500, 'GH_NOT_FOUND'],
    ['UnmergedWorkError', new UnmergedWorkError(['foo', 'bar']), 409, 'UNMERGED_WORK'],
    ['INVALID_ARGS', new PpgError('bad args', 'INVALID_ARGS'), 400, 'INVALID_ARGS'],
    ['NO_SESSION_ID', new PpgError('no session', 'NO_SESSION_ID'), 400, 'NO_SESSION_ID'],
    ['AGENTS_RUNNING', new PpgError('running', 'AGENTS_RUNNING'), 409, 'AGENTS_RUNNING'],
    ['WAIT_TIMEOUT', new PpgError('timeout', 'WAIT_TIMEOUT'), 408, 'WAIT_TIMEOUT'],
    ['AGENTS_FAILED', new PpgError('failed', 'AGENTS_FAILED'), 500, 'AGENTS_FAILED'],
    ['PANE_NOT_FOUND', new PpgError('pane gone', 'PANE_NOT_FOUND'), 404, 'PANE_NOT_FOUND'],
    ['NO_TMUX_WINDOW', new PpgError('no window', 'NO_TMUX_WINDOW'), 404, 'NO_TMUX_WINDOW'],
    ['TARGET_NOT_FOUND', new PpgError('no target', 'TARGET_NOT_FOUND'), 404, 'TARGET_NOT_FOUND'],
    ['DOWNLOAD_FAILED', new PpgError('download err', 'DOWNLOAD_FAILED'), 502, 'DOWNLOAD_FAILED'],
    ['INSTALL_FAILED', new PpgError('install err', 'INSTALL_FAILED'), 500, 'INSTALL_FAILED'],
  ])('given %s, should return %d with code %s', (_label, error, expectedStatus, expectedCode) => {
    const { status, body } = buildErrorResponse(error);
    expect(status).toBe(expectedStatus);
    expect(body.error.code).toBe(expectedCode);
    expect(body.error.message).toBe(error.message);
  });

  test('given Fastify validation error, should return 400 with field details', () => {
    const validationDetails = [
      { instancePath: '/name', message: 'must be string' },
      { instancePath: '/count', message: 'must be number' },
    ];
    const error = Object.assign(new Error('body/name must be string'), {
      validation: validationDetails,
      validationContext: 'body',
    });

    const { status, body } = buildErrorResponse(error);

    expect(status).toBe(400);
    expect(body).toEqual({
      error: {
        code: 'VALIDATION_ERROR',
        message: 'body/name must be string',
        details: validationDetails,
      },
    });
  });

  test('given unknown error, should return generic 500', () => {
    const { status, body } = buildErrorResponse(new Error('something broke internally'));

    expect(status).toBe(500);
    expect(body).toEqual({
      error: {
        code: 'INTERNAL_ERROR',
        message: 'An unexpected error occurred',
      },
    });
  });

  test('given unknown error, should not leak internal message', () => {
    const { body } = buildErrorResponse(new TypeError('Cannot read property x of undefined'));
    expect(body.error.message).toBe('An unexpected error occurred');
  });

  test('given unknown error and log function, should log the original error', () => {
    const log: LogFn = vi.fn();
    const error = new Error('db connection lost');

    buildErrorResponse(error, log);

    expect(log).toHaveBeenCalledWith('Unhandled error', error);
  });

  test('given PpgError and log function, should not log', () => {
    const log: LogFn = vi.fn();
    buildErrorResponse(new WorktreeNotFoundError('wt-x'), log);
    expect(log).not.toHaveBeenCalled();
  });
});

describe('errorHandler', () => {
  const mockReply = () => ({
    status: vi.fn().mockReturnThis(),
    send: vi.fn().mockReturnThis(),
  });

  const mockRequest = { log: { error: vi.fn() } } as unknown as Parameters<typeof errorHandler>[1];

  test('given PpgError, should send structured response', () => {
    const reply = mockReply();
    errorHandler(new AgentNotFoundError('ag-xyz'), mockRequest, reply as never);

    expect(reply.status).toHaveBeenCalledWith(404);
    expect(reply.send).toHaveBeenCalledWith({
      error: {
        code: 'AGENT_NOT_FOUND',
        message: 'Agent not found: ag-xyz',
      },
    });
  });

  test('given unknown error, should send 500 and log via request.log', () => {
    const request = { log: { error: vi.fn() } } as unknown as Parameters<typeof errorHandler>[1];
    const reply = mockReply();
    const error = new Error('oops');

    errorHandler(error, request, reply as never);

    expect(reply.status).toHaveBeenCalledWith(500);
    expect(reply.send).toHaveBeenCalledWith({
      error: {
        code: 'INTERNAL_ERROR',
        message: 'An unexpected error occurred',
      },
    });
    expect(request.log.error).toHaveBeenCalledWith({ err: error }, 'Unhandled error');
  });
});

describe('registerErrorHandler', () => {
  test('given Fastify instance, should call setErrorHandler', () => {
    const app = { setErrorHandler: vi.fn() };
    registerErrorHandler(app as never);

    expect(app.setErrorHandler).toHaveBeenCalledOnce();
    expect(app.setErrorHandler).toHaveBeenCalledWith(errorHandler);
  });
});
