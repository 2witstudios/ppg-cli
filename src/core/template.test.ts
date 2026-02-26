import { describe, test, expect } from 'vitest';
import { renderTemplate, type TemplateContext } from './template.js';

const baseContext: TemplateContext = {
  WORKTREE_PATH: '/tmp/wt',
  BRANCH: 'ppg/feat',
  AGENT_ID: 'ag-test1234',
  RESULT_FILE: '/tmp/.ppg/results/ag-test1234.md',
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
