import type { FastifyError, FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { PpgError } from '../lib/errors.js';

export interface ErrorResponseBody {
  error: {
    code: string;
    message: string;
    details?: unknown;
  };
}

const httpStatusByCode: Record<string, number> = {
  INVALID_ARGS: 400,
  NO_SESSION_ID: 400,
  NOT_GIT_REPO: 400,
  NOT_INITIALIZED: 409,
  MANIFEST_LOCK: 409,
  AGENTS_RUNNING: 409,
  MERGE_FAILED: 409,
  UNMERGED_WORK: 409,
  WORKTREE_NOT_FOUND: 404,
  AGENT_NOT_FOUND: 404,
  WAIT_TIMEOUT: 408,
  AGENTS_FAILED: 500,
  TMUX_NOT_FOUND: 500,
  GH_NOT_FOUND: 500,
};

export function getHttpStatus(ppgCode: string): number {
  return httpStatusByCode[ppgCode] ?? 500;
}

function isFastifyValidationError(
  error: Error | FastifyError,
): error is FastifyError & { validation: unknown[] } {
  return 'validation' in error && Array.isArray((error as FastifyError).validation);
}

export function buildErrorResponse(error: Error): {
  status: number;
  body: ErrorResponseBody;
} {
  if (error instanceof PpgError) {
    return {
      status: getHttpStatus(error.code),
      body: {
        error: {
          code: error.code,
          message: error.message,
        },
      },
    };
  }

  if (isFastifyValidationError(error)) {
    return {
      status: 400,
      body: {
        error: {
          code: 'VALIDATION_ERROR',
          message: error.message,
          details: (error as FastifyError).validation,
        },
      },
    };
  }

  return {
    status: 500,
    body: {
      error: {
        code: 'INTERNAL_ERROR',
        message: 'An unexpected error occurred',
      },
    },
  };
}

export function errorHandler(
  error: Error,
  _request: FastifyRequest,
  reply: FastifyReply,
): void {
  const { status, body } = buildErrorResponse(error);
  reply.status(status).send(body);
}

export function registerErrorHandler(app: FastifyInstance): void {
  app.setErrorHandler(errorHandler);
}
