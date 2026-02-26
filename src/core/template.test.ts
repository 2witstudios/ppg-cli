import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { describe, test, expect, beforeEach, afterEach, vi } from 'vitest';
import { renderTemplate, listTemplates, listTemplatesWithSource, loadTemplate, type TemplateContext } from './template.js';

const baseContext: TemplateContext = {
  WORKTREE_PATH: '/tmp/wt',
  BRANCH: 'ppg/feat',
  AGENT_ID: 'ag-test1234',
  PROJECT_ROOT: '/tmp/project',
};

describe('renderTemplate', () => {
  test('given basic placeholders, should substitute values', () => {
    const result = renderTemplate('Path: {{WORKTREE_PATH}}, Branch: {{BRANCH}}', baseContext);
    expect(result).toBe('Path: /tmp/wt, Branch: ppg/feat');
  });

  test('given missing vars, should leave placeholder unchanged', () => {
    const result = renderTemplate('Hello {{UNKNOWN_VAR}}!', baseContext);
    expect(result).toBe('Hello {{UNKNOWN_VAR}}!');
  });

  test('given empty template, should return empty string', () => {
    const result = renderTemplate('', baseContext);
    expect(result).toBe('');
  });

  test('given no placeholders, should return content unchanged', () => {
    const result = renderTemplate('No vars here', baseContext);
    expect(result).toBe('No vars here');
  });

  test('given adjacent placeholders, should substitute both', () => {
    const result = renderTemplate('{{AGENT_ID}}{{BRANCH}}', baseContext);
    expect(result).toBe('ag-test1234ppg/feat');
  });

  test('given multiple occurrences of same var, should replace all', () => {
    const result = renderTemplate('{{AGENT_ID}} and {{AGENT_ID}}', baseContext);
    expect(result).toBe('ag-test1234 and ag-test1234');
  });

  test('given triple braces, should only match inner pair', () => {
    const result = renderTemplate('{{{AGENT_ID}}}', baseContext);
    expect(result).toBe('{ag-test1234}');
  });

  test('given custom context keys, should substitute them', () => {
    const ctx: TemplateContext = {
      ...baseContext,
      TASK_NAME: 'auth-feature',
    };
    const result = renderTemplate('Task: {{TASK_NAME}}', ctx);
    expect(result).toBe('Task: auth-feature');
  });

  test('given non-word characters in braces, should not match', () => {
    const result = renderTemplate('{{NOT-VALID}} {{NOT VALID}}', baseContext);
    expect(result).toBe('{{NOT-VALID}} {{NOT VALID}}');
  });
});

// Tests for global template resolution
let TMP_ROOT: string;
let GLOBAL_TMP: string;

vi.mock('../lib/paths.js', async () => {
  const actual = await vi.importActual<typeof import('../lib/paths.js')>('../lib/paths.js');
  return {
    ...actual,
    globalTemplatesDir: () => path.join(GLOBAL_TMP, '.ppg', 'templates'),
  };
});

beforeEach(async () => {
  TMP_ROOT = await fs.mkdtemp(path.join(os.tmpdir(), 'ppg-tmpl-test-'));
  GLOBAL_TMP = await fs.mkdtemp(path.join(os.tmpdir(), 'ppg-tmpl-global-'));
  await fs.mkdir(path.join(TMP_ROOT, '.ppg', 'templates'), { recursive: true });
  await fs.mkdir(path.join(GLOBAL_TMP, '.ppg', 'templates'), { recursive: true });
});

afterEach(async () => {
  await fs.rm(TMP_ROOT, { recursive: true, force: true });
  await fs.rm(GLOBAL_TMP, { recursive: true, force: true });
});

describe('listTemplates', () => {
  test('given only local templates, should return local names', async () => {
    await fs.writeFile(path.join(TMP_ROOT, '.ppg', 'templates', 'local.md'), '# Local');

    const result = await listTemplates(TMP_ROOT);

    expect(result).toEqual(['local']);
  });

  test('given only global templates, should return global names', async () => {
    await fs.writeFile(path.join(GLOBAL_TMP, '.ppg', 'templates', 'global.md'), '# Global');

    const result = await listTemplates(TMP_ROOT);

    expect(result).toEqual(['global']);
  });

  test('given name conflict, should only include local', async () => {
    await fs.writeFile(path.join(TMP_ROOT, '.ppg', 'templates', 'shared.md'), '# Local');
    await fs.writeFile(path.join(GLOBAL_TMP, '.ppg', 'templates', 'shared.md'), '# Global');

    const result = await listTemplates(TMP_ROOT);

    expect(result).toEqual(['shared']);
  });

  test('given both local and global, should include all unique names', async () => {
    await fs.writeFile(path.join(TMP_ROOT, '.ppg', 'templates', 'local.md'), '# Local');
    await fs.writeFile(path.join(GLOBAL_TMP, '.ppg', 'templates', 'global.md'), '# Global');

    const result = await listTemplates(TMP_ROOT);

    expect(result).toEqual(expect.arrayContaining(['local', 'global']));
    expect(result).toHaveLength(2);
  });
});

describe('listTemplatesWithSource', () => {
  test('given local and global templates, should annotate source correctly', async () => {
    await fs.writeFile(path.join(TMP_ROOT, '.ppg', 'templates', 'local.md'), '# Local');
    await fs.writeFile(path.join(GLOBAL_TMP, '.ppg', 'templates', 'global.md'), '# Global');

    const result = await listTemplatesWithSource(TMP_ROOT);

    expect(result).toEqual([
      { name: 'local', source: 'local' },
      { name: 'global', source: 'global' },
    ]);
  });

  test('given name conflict, should only include local version', async () => {
    await fs.writeFile(path.join(TMP_ROOT, '.ppg', 'templates', 'shared.md'), '# Local');
    await fs.writeFile(path.join(GLOBAL_TMP, '.ppg', 'templates', 'shared.md'), '# Global');

    const result = await listTemplatesWithSource(TMP_ROOT);

    expect(result).toEqual([{ name: 'shared', source: 'local' }]);
  });
});

describe('loadTemplate', () => {
  test('given local template exists, should load local', async () => {
    await fs.writeFile(path.join(TMP_ROOT, '.ppg', 'templates', 'test.md'), '# Local content');

    const result = await loadTemplate(TMP_ROOT, 'test');

    expect(result).toBe('# Local content');
  });

  test('given only global template exists, should load global', async () => {
    await fs.writeFile(path.join(GLOBAL_TMP, '.ppg', 'templates', 'global-only.md'), '# Global content');

    const result = await loadTemplate(TMP_ROOT, 'global-only');

    expect(result).toBe('# Global content');
  });

  test('given both local and global exist, should prefer local', async () => {
    await fs.writeFile(path.join(TMP_ROOT, '.ppg', 'templates', 'shared.md'), '# Local wins');
    await fs.writeFile(path.join(GLOBAL_TMP, '.ppg', 'templates', 'shared.md'), '# Global loses');

    const result = await loadTemplate(TMP_ROOT, 'shared');

    expect(result).toBe('# Local wins');
  });

  test('given neither exists, should throw', async () => {
    await expect(loadTemplate(TMP_ROOT, 'missing')).rejects.toThrow();
  });
});
