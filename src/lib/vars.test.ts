import { describe, test, expect } from 'vitest';
import { parseVars } from './vars.js';
import { PgError } from './errors.js';

describe('parseVars', () => {
  test('given valid KEY=value pairs, should return a record', () => {
    expect(parseVars(['FOO=bar', 'BAZ=qux'])).toEqual({ FOO: 'bar', BAZ: 'qux' });
  });

  test('given value containing =, should preserve everything after first =', () => {
    expect(parseVars(['CONN=host=localhost;port=5432'])).toEqual({
      CONN: 'host=localhost;port=5432',
    });
  });

  test('given empty value, should allow it', () => {
    expect(parseVars(['KEY='])).toEqual({ KEY: '' });
  });

  test('given no = sign, should throw PgError with INVALID_ARGS', () => {
    try {
      parseVars(['NOEQUALS']);
      expect.fail('should have thrown');
    } catch (err) {
      expect(err).toBeInstanceOf(PgError);
      expect((err as PgError).code).toBe('INVALID_ARGS');
      expect((err as PgError).message).toContain('Invalid --var format');
    }
  });

  test('given empty key (=value), should throw PgError with INVALID_ARGS', () => {
    try {
      parseVars(['=value']);
      expect.fail('should have thrown');
    } catch (err) {
      expect(err).toBeInstanceOf(PgError);
      expect((err as PgError).code).toBe('INVALID_ARGS');
      expect((err as PgError).message).toContain('Invalid --var format');
    }
  });

  test('given empty array, should return empty record', () => {
    expect(parseVars([])).toEqual({});
  });
});
