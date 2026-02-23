import fs from 'node:fs/promises';
import path from 'node:path';
import { execa } from 'execa';
import { pgDir, resultsDir, logsDir, templatesDir, promptsDir, manifestPath } from '../lib/paths.js';
import { NotGitRepoError, TmuxNotFoundError } from '../lib/errors.js';
import { success, info } from '../lib/output.js';
import { writeDefaultConfig } from '../core/config.js';
import { createEmptyManifest, writeManifest } from '../core/manifest.js';

const DEFAULT_TEMPLATE = `# Task: {{TASK_NAME}}

## Context
You are working in a git worktree at: {{WORKTREE_PATH}}
Branch: {{BRANCH}}
Project root: {{PROJECT_ROOT}}

## Instructions
{{PROMPT}}

## Result Reporting
When you have completed the task, write your results to:
{{RESULT_FILE}}
`;

export async function initCommand(options: { json?: boolean }): Promise<void> {
  const cwd = process.cwd();

  // 1. Verify git repo
  let projectRoot: string;
  try {
    const result = await execa('git', ['rev-parse', '--show-toplevel'], { cwd });
    projectRoot = result.stdout.trim();
  } catch {
    throw new NotGitRepoError(cwd);
  }

  // 2. Check tmux available
  try {
    await execa('tmux', ['-V']);
  } catch {
    throw new TmuxNotFoundError();
  }

  // 3. Create directories
  const dirs = [
    pgDir(projectRoot),
    resultsDir(projectRoot),
    logsDir(projectRoot),
    templatesDir(projectRoot),
    promptsDir(projectRoot),
  ];

  for (const dir of dirs) {
    await fs.mkdir(dir, { recursive: true });
  }

  info('Created .pg/ directory structure');

  // 4. Write default config
  await writeDefaultConfig(projectRoot);
  info('Wrote default config.yaml');

  // 5. Write empty manifest
  const dirName = path.basename(projectRoot);
  const sessionName = `ppg-${dirName}`;
  const manifest = createEmptyManifest(projectRoot, sessionName);
  await writeManifest(projectRoot, manifest);
  info('Wrote empty manifest.json');

  // 6. Update .gitignore
  await updateGitignore(projectRoot);
  info('Updated .gitignore');

  // 7. Write sample template
  const templatePath = path.join(templatesDir(projectRoot), 'default.md');
  try {
    await fs.access(templatePath);
  } catch {
    await fs.writeFile(templatePath, DEFAULT_TEMPLATE, 'utf-8');
    info('Wrote sample template: default.md');
  }

  if (options.json) {
    console.log(JSON.stringify({
      success: true,
      projectRoot,
      sessionName,
      pgDir: pgDir(projectRoot),
    }));
  } else {
    success(`Point Guard initialized in ${projectRoot}`);
  }
}

async function updateGitignore(projectRoot: string): Promise<void> {
  const gitignorePath = path.join(projectRoot, '.gitignore');
  const entriesToAdd = [
    '.pg/results/',
    '.pg/logs/',
    '.pg/manifest.json',
    '.pg/prompts/',
  ];

  let content = '';
  try {
    content = await fs.readFile(gitignorePath, 'utf-8');
  } catch {
    // No .gitignore yet
  }

  const lines = content.split('\n');
  const toAdd = entriesToAdd.filter((entry) => !lines.includes(entry));

  if (toAdd.length > 0) {
    const addition = (content.endsWith('\n') || content === '' ? '' : '\n')
      + '\n# Point Guard\n'
      + toAdd.join('\n')
      + '\n';
    await fs.appendFile(gitignorePath, addition, 'utf-8');
  }
}
