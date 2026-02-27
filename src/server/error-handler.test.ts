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
    ['WAIT_TIMEOUT', 408],
    ['AGENTS_FAILED', 500],
    ['TMUX_NOT_FOUND', 500],
    ['GH_NOT_FOUND', 500],
  ])('maps %s → %d', (code, expected) => {
    expect(getHttpStatus(code)).toBe(expected);
  });

  test('returns 500 for unknown code', () => {
    expect(getHttpStatus('SOME_UNKNOWN_CODE')).toBe(500);
  });
});

describe('buildErrorResponse', () => {
  test('handles PpgError with mapped status', () => {
    const error = new WorktreeNotFoundError('wt-abc123');
    const { status, body } = buildErrorResponse(error);

    expect(status).toBe(404);
    expect(body).toEqual({
      error: {
        code: 'WORKTREE_NOT_FOUND',
        message: 'Worktree not found: wt-abc123',
      },
    });
  });

  test.each([
    [new TmuxNotFoundError(), 500, 'TMUX_NOT_FOUND'],
    [new NotGitRepoError('/tmp'), 400, 'NOT_GIT_REPO'],
    [new NotInitializedError('/tmp'), 409, 'NOT_INITIALIZED'],
    [new ManifestLockError(), 409, 'MANIFEST_LOCK'],
    [new WorktreeNotFoundError('wt-x'), 404, 'WORKTREE_NOT_FOUND'],
    [new AgentNotFoundError('ag-y'), 404, 'AGENT_NOT_FOUND'],
    [new MergeFailedError('conflict'), 409, 'MERGE_FAILED'],
    [new GhNotFoundError(), 500, 'GH_NOT_FOUND'],
    [new UnmergedWorkError(['foo', 'bar']), 409, 'UNMERGED_WORK'],
    [new PpgError('bad args', 'INVALID_ARGS'), 400, 'INVALID_ARGS'],
    [new PpgError('no session', 'NO_SESSION_ID'), 400, 'NO_SESSION_ID'],
    [new PpgError('running', 'AGENTS_RUNNING'), 409, 'AGENTS_RUNNING'],
    [new PpgError('timeout', 'WAIT_TIMEOUT'), 408, 'WAIT_TIMEOUT'],
    [new PpgError('failed', 'AGENTS_FAILED'), 500, 'AGENTS_FAILED'],
  ])('handles %s → %d', (error, expectedStatus, expectedCode) => {
    const { status, body } = buildErrorResponse(error);
    expect(status).toBe(expectedStatus);
    expect(body.error.code).toBe(expectedCode);
    expect(body.error.message).toBe(error.message);
  });

  test('handles Fastify validation error', () => {
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

  test('handles unknown error with generic 500', () => {
    const error = new Error('something broke internally');
    const { status, body } = buildErrorResponse(error);

    expect(status).toBe(500);
    expect(body).toEqual({
      error: {
        code: 'INTERNAL_ERROR',
        message: 'An unexpected error occurred',
      },
    });
  });

  test('does not leak internal message for unknown errors', () => {
    const error = new TypeError('Cannot read property x of undefined');
    const { body } = buildErrorResponse(error);
    expect(body.error.message).toBe('An unexpected error occurred');
    expect(body.error.message).not.toContain('Cannot read');
  });
});

describe('errorHandler', () => {
  const mockReply = () => {
    const reply = {
      status: vi.fn().mockReturnThis(),
      send: vi.fn().mockReturnThis(),
    };
    return reply;
  };

  const mockRequest = {} as Parameters<typeof errorHandler>[1];

  test('sends PpgError as structured response', () => {
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

  test('sends unknown error as 500', () => {
    const reply = mockReply();
    errorHandler(new Error('oops'), mockRequest, reply as never);

    expect(reply.status).toHaveBeenCalledWith(500);
    expect(reply.send).toHaveBeenCalledWith({
      error: {
        code: 'INTERNAL_ERROR',
        message: 'An unexpected error occurred',
      },
    });
  });
});

describe('registerErrorHandler', () => {
  test('calls setErrorHandler on the Fastify instance', () => {
    const app = { setErrorHandler: vi.fn() };
    registerErrorHandler(app as never);

    expect(app.setErrorHandler).toHaveBeenCalledOnce();
    expect(app.setErrorHandler).toHaveBeenCalledWith(errorHandler);
  });
});
