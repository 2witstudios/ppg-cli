import fp from 'fastify-plugin';
import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { PpgError } from '../lib/errors.js';

export interface ErrorResponseBody {
  error: {
    code: string;
    message: string;
  };
}

function errorHandler(
  error: Error & { statusCode?: number; validation?: unknown },
  request: FastifyRequest,
  reply: FastifyReply,
): void {
  if (error instanceof PpgError) {
    request.log.warn({ err: error, code: error.code }, error.message);
    reply.status(error.exitCode >= 400 ? error.exitCode : 400).send({
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

export { errorHandler };
