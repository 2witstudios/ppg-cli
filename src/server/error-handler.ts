import fp from 'fastify-plugin';
import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { PpgError } from '../lib/errors.js';

export interface ErrorResponseBody {
  error: {
    code: string;
    message: string;
  };
}

const httpStatusByCode: Record<string, number> = {
  WORKTREE_NOT_FOUND: 404,
  AGENT_NOT_FOUND: 404,
  NOT_INITIALIZED: 400,
  NOT_GIT_REPO: 400,
  INVALID_ARGS: 400,
  MANIFEST_LOCK: 409,
  MERGE_FAILED: 409,
  AGENTS_RUNNING: 409,
  TMUX_NOT_FOUND: 500,
  GH_NOT_FOUND: 500,
  UNMERGED_WORK: 409,
  WAIT_TIMEOUT: 504,
  AGENTS_FAILED: 502,
  NO_SESSION_ID: 400,
};

const defaultPpgStatus = 400;

function httpStatusForPpgError(code: string): number {
  return httpStatusByCode[code] ?? defaultPpgStatus;
}

function errorHandler(
  error: Error & { statusCode?: number; validation?: unknown },
  request: FastifyRequest,
  reply: FastifyReply,
): void {
  if (error instanceof PpgError) {
    const status = httpStatusForPpgError(error.code);
    request.log.warn({ err: error, code: error.code }, error.message);
    reply.status(status).send({
      error: { code: error.code, message: error.message },
    } satisfies ErrorResponseBody);
    return;
  }

  // Fastify validation errors (e.g. schema validation)
  if (error.validation) {
    request.log.warn({ err: error }, 'Validation error');
    reply.status(400).send({
      error: { code: 'VALIDATION_ERROR', message: error.message },
    } satisfies ErrorResponseBody);
    return;
  }

  // Unexpected errors — log full details, return safe response
  request.log.error(error, 'Unhandled error');
  const statusCode =
    error.statusCode && error.statusCode >= 400 ? error.statusCode : 500;
  reply.status(statusCode).send({
    error: {
      code: 'INTERNAL_ERROR',
      message:
        process.env['NODE_ENV'] === 'production'
          ? 'Internal server error'
          : error.message,
    },
  } satisfies ErrorResponseBody);
}

export default fp(
  async function errorHandlerPlugin(fastify: FastifyInstance) {
    fastify.setErrorHandler(errorHandler);
  },
  { name: 'ppg-error-handler' },
);

export { errorHandler, httpStatusForPpgError };
