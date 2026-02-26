import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { describe, test, expect, beforeEach, afterEach } from 'vitest';
import { listSwarms, loadSwarm } from './swarm.js';

let TMP_ROOT: string;
let SWARMS_DIR: string;

beforeEach(async () => {
  TMP_ROOT = await fs.mkdtemp(path.join(os.tmpdir(), 'ppg-swarm-test-'));
  SWARMS_DIR = path.join(TMP_ROOT, '.ppg', 'swarms');
  await fs.mkdir(SWARMS_DIR, { recursive: true });
});

afterEach(async () => {
  await fs.rm(TMP_ROOT, { recursive: true, force: true });
});

const validYaml = `name: code-review
description: Multi-perspective code review
strategy: shared

agents:
  - prompt: review-quality
  - prompt: review-security
`;

describe('listSwarms', () => {
  test('given a directory with .yaml files, should return names without extension', async () => {
    await fs.writeFile(path.join(SWARMS_DIR, 'code-review.yaml'), validYaml);
    await fs.writeFile(path.join(SWARMS_DIR, 'deploy.yaml'), validYaml);

    const actual = await listSwarms(TMP_ROOT);

    expect(actual).toHaveLength(2);
    expect(actual).toEqual(expect.arrayContaining(['code-review', 'deploy']));
  });

  test('given a directory with .yml files, should return names without extension', async () => {
    await fs.writeFile(path.join(SWARMS_DIR, 'legacy.yml'), validYaml);

    const actual = await listSwarms(TMP_ROOT);

    expect(actual).toEqual(['legacy']);
  });

  test('given a directory with mixed yaml and non-yaml files, should only return yaml files', async () => {
    await fs.writeFile(path.join(SWARMS_DIR, 'good.yaml'), validYaml);
    await fs.writeFile(path.join(SWARMS_DIR, 'readme.md'), '# README');
    await fs.writeFile(path.join(SWARMS_DIR, 'notes.txt'), 'notes');

    const actual = await listSwarms(TMP_ROOT);

    expect(actual).toEqual(['good']);
  });

  test('given a nonexistent swarms directory, should return empty array', async () => {
    await fs.rm(SWARMS_DIR, { recursive: true, force: true });

    const actual = await listSwarms(TMP_ROOT);

    expect(actual).toEqual([]);
  });

  test('given an empty directory, should return empty array', async () => {
    const actual = await listSwarms(TMP_ROOT);

    expect(actual).toEqual([]);
  });
});

describe('loadSwarm', () => {
  test('given valid YAML with .yaml extension, should parse correctly', async () => {
    await fs.writeFile(path.join(SWARMS_DIR, 'code-review.yaml'), validYaml);

    const actual = await loadSwarm(TMP_ROOT, 'code-review');

    expect(actual).toEqual({
      name: 'code-review',
      description: 'Multi-perspective code review',
      strategy: 'shared',
      agents: [
        { prompt: 'review-quality' },
        { prompt: 'review-security' },
      ],
    });
  });

  test('given valid YAML with .yml extension, should fall back and parse', async () => {
    await fs.writeFile(path.join(SWARMS_DIR, 'legacy.yml'), validYaml);

    const actual = await loadSwarm(TMP_ROOT, 'legacy');

    expect(actual.name).toBe('code-review');
    expect(actual.agents).toHaveLength(2);
  });

  test('given no strategy field, should default to shared', async () => {
    const yaml = `name: test-swarm
agents:
  - prompt: review-quality
`;
    await fs.writeFile(path.join(SWARMS_DIR, 'test-swarm.yaml'), yaml);

    const actual = await loadSwarm(TMP_ROOT, 'test-swarm');

    expect(actual.strategy).toBe('shared');
  });

  test('given no description field, should default to empty string', async () => {
    const yaml = `name: test-swarm
agents:
  - prompt: review-quality
`;
    await fs.writeFile(path.join(SWARMS_DIR, 'test-swarm.yaml'), yaml);

    const actual = await loadSwarm(TMP_ROOT, 'test-swarm');

    expect(actual.description).toBe('');
  });

  test('given isolated strategy, should accept it', async () => {
    const yaml = `name: test-swarm
strategy: isolated
agents:
  - prompt: review-quality
`;
    await fs.writeFile(path.join(SWARMS_DIR, 'test-swarm.yaml'), yaml);

    const actual = await loadSwarm(TMP_ROOT, 'test-swarm');

    expect(actual.strategy).toBe('isolated');
  });

  test('given agent with optional overrides, should preserve them', async () => {
    const yaml = `name: test-swarm
agents:
  - prompt: review-quality
    agent: codex
    vars:
      EXTRA: "be thorough"
`;
    await fs.writeFile(path.join(SWARMS_DIR, 'test-swarm.yaml'), yaml);

    const actual = await loadSwarm(TMP_ROOT, 'test-swarm');

    expect(actual.agents[0]).toEqual({
      prompt: 'review-quality',
      agent: 'codex',
      vars: { EXTRA: 'be thorough' },
    });
  });

  test('given empty YAML file, should throw INVALID_ARGS', async () => {
    await fs.writeFile(path.join(SWARMS_DIR, 'empty.yaml'), '');

    await expect(loadSwarm(TMP_ROOT, 'empty'))
      .rejects.toThrow('empty or malformed YAML');
  });

  test('given nonexistent template, should throw INVALID_ARGS', async () => {
    await expect(loadSwarm(TMP_ROOT, 'nope'))
      .rejects.toThrow('Swarm template not found: nope');
  });

  test('given YAML missing name field, should throw INVALID_ARGS', async () => {
    const yaml = `agents:
  - prompt: review-quality
`;
    await fs.writeFile(path.join(SWARMS_DIR, 'bad.yaml'), yaml);

    await expect(loadSwarm(TMP_ROOT, 'bad'))
      .rejects.toThrow('missing name or agents');
  });

  test('given YAML missing agents field, should throw INVALID_ARGS', async () => {
    const yaml = `name: test-swarm
`;
    await fs.writeFile(path.join(SWARMS_DIR, 'bad.yaml'), yaml);

    await expect(loadSwarm(TMP_ROOT, 'bad'))
      .rejects.toThrow('missing name or agents');
  });

  test('given invalid strategy, should throw INVALID_ARGS', async () => {
    const yaml = `name: test-swarm
strategy: parallel
agents:
  - prompt: review-quality
`;
    await fs.writeFile(path.join(SWARMS_DIR, 'bad.yaml'), yaml);

    await expect(loadSwarm(TMP_ROOT, 'bad'))
      .rejects.toThrow("Must be 'shared' or 'isolated'");
  });

  test('given agent missing prompt field, should throw INVALID_ARGS', async () => {
    const yaml = `name: test-swarm
agents:
  - agent: claude
`;
    await fs.writeFile(path.join(SWARMS_DIR, 'bad.yaml'), yaml);

    await expect(loadSwarm(TMP_ROOT, 'bad'))
      .rejects.toThrow('agent[0] missing prompt field');
  });

  test('given agent with path traversal in prompt name, should throw INVALID_ARGS', async () => {
    const yaml = `name: test-swarm
agents:
  - prompt: "../../etc/passwd"
`;
    await fs.writeFile(path.join(SWARMS_DIR, 'bad.yaml'), yaml);

    await expect(loadSwarm(TMP_ROOT, 'bad'))
      .rejects.toThrow('must be alphanumeric, hyphens, or underscores');
  });

  test('given agent with slash in prompt name, should throw INVALID_ARGS', async () => {
    const yaml = `name: test-swarm
agents:
  - prompt: "sub/dir"
`;
    await fs.writeFile(path.join(SWARMS_DIR, 'bad.yaml'), yaml);

    await expect(loadSwarm(TMP_ROOT, 'bad'))
      .rejects.toThrow('must be alphanumeric, hyphens, or underscores');
  });

  test('given agent with underscores and hyphens in prompt name, should accept', async () => {
    const yaml = `name: test-swarm
agents:
  - prompt: review_quality-v2
`;
    await fs.writeFile(path.join(SWARMS_DIR, 'test-swarm.yaml'), yaml);

    const actual = await loadSwarm(TMP_ROOT, 'test-swarm');

    expect(actual.agents[0].prompt).toBe('review_quality-v2');
  });

  test('given template name with path traversal, should throw INVALID_ARGS', async () => {
    await expect(loadSwarm(TMP_ROOT, '../../etc/passwd'))
      .rejects.toThrow('Invalid swarm template name');
  });

  test('given template name with slashes, should throw INVALID_ARGS', async () => {
    await expect(loadSwarm(TMP_ROOT, 'sub/dir'))
      .rejects.toThrow('Invalid swarm template name');
  });

  test('given template name with spaces, should throw INVALID_ARGS', async () => {
    await expect(loadSwarm(TMP_ROOT, 'bad name'))
      .rejects.toThrow('Invalid swarm template name');
  });

  test('given YAML with unsafe swarm name, should throw INVALID_ARGS', async () => {
    const yaml = `name: "../../bad"
agents:
  - prompt: review-quality
`;
    await fs.writeFile(path.join(SWARMS_DIR, 'sneaky.yaml'), yaml);

    await expect(loadSwarm(TMP_ROOT, 'sneaky'))
      .rejects.toThrow('Invalid swarm name');
  });

  test('given YAML with spaces in swarm name, should throw INVALID_ARGS', async () => {
    const yaml = `name: "bad name"
agents:
  - prompt: review-quality
`;
    await fs.writeFile(path.join(SWARMS_DIR, 'bad-name.yaml'), yaml);

    await expect(loadSwarm(TMP_ROOT, 'bad-name'))
      .rejects.toThrow('Invalid swarm name');
  });
});
