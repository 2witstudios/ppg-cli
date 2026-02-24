import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execa } from 'execa';
import { pgDir, resultsDir, logsDir, templatesDir, promptsDir, promptFile, swarmsDir, manifestPath } from '../lib/paths.js';
import { NotGitRepoError, TmuxNotFoundError } from '../lib/errors.js';
import { success, info } from '../lib/output.js';
import { writeDefaultConfig } from '../core/config.js';
import { createEmptyManifest, writeManifest } from '../core/manifest.js';
import { bundledPrompts } from '../bundled/prompts.js';
import { bundledSwarms } from '../bundled/swarms.js';

const CONDUCTOR_CONTEXT = `# PPG Conductor Context

You are operating on the master branch of a ppg-managed project.

## Critical Rule
**NEVER make code changes directly on the master branch.** Use \`ppg spawn\` to create worktrees.

## Quick Reference
- \`ppg spawn --name <name> --prompt "<task>" --json --no-open\` — Spawn worktree + agent
- \`ppg status --json\` — Check statuses
- \`ppg aggregate --all --json\` — Collect results
- \`ppg merge <wt-id> --json\` — Merge completed work
- \`ppg kill --agent <id> --json\` — Kill agent

## Workflow
1. Break request into parallelizable tasks
2. Spawn each: \`ppg spawn --name <name> --prompt "<self-contained prompt>" --json --no-open\`
3. Poll: \`ppg status --json\` every 5s
4. Aggregate: \`ppg aggregate --all --json\`
5. Present results, then merge confirmed worktrees

Each agent prompt must be self-contained — agents have no memory of this conversation.
Always use \`--json --no-open\`.
`;

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
    swarmsDir(projectRoot),
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

  // 8. Write bundled prompt files
  for (const [name, content] of Object.entries(bundledPrompts)) {
    const pPath = promptFile(projectRoot, name);
    try {
      await fs.access(pPath);
    } catch {
      await fs.writeFile(pPath, content, 'utf-8');
      info(`Wrote prompt: ${name}.md`);
    }
  }

  // 9. Write bundled swarm templates
  for (const [name, content] of Object.entries(bundledSwarms)) {
    const sPath = path.join(swarmsDir(projectRoot), `${name}.yaml`);
    try {
      await fs.access(sPath);
    } catch {
      await fs.writeFile(sPath, content, 'utf-8');
      info(`Wrote swarm template: ${name}.yaml`);
    }
  }

  // 10. Write conductor context
  const conductorPath = path.join(pgDir(projectRoot), 'conductor-context.md');
  await fs.writeFile(conductorPath, CONDUCTOR_CONTEXT, 'utf-8');
  info('Wrote conductor-context.md');

  // 11. Register Claude Code plugin
  const pluginRegistered = await registerClaudePlugin();
  if (pluginRegistered) {
    info('Registered ppg Claude Code plugin');
  }

  if (options.json) {
    console.log(JSON.stringify({
      success: true,
      projectRoot,
      sessionName,
      pgDir: pgDir(projectRoot),
      pluginRegistered,
    }));
  } else {
    success(`Point Guard initialized in ${projectRoot}`);
  }
}

async function registerClaudePlugin(): Promise<boolean> {
  try {
    const home = process.env.HOME;
    if (!home) return false;

    const skillsDir = path.join(home, '.claude', 'skills');

    // Find this package's skills directory
    // Works from both dist/cli.js (../skills/) and src/commands/init.ts (../../skills/)
    const __dirname = path.dirname(fileURLToPath(import.meta.url));
    let srcSkillsDir = path.resolve(__dirname, '..', 'skills');
    try {
      await fs.access(srcSkillsDir);
    } catch {
      srcSkillsDir = path.resolve(__dirname, '..', '..', 'skills');
      try {
        await fs.access(srcSkillsDir);
      } catch {
        return false;
      }
    }

    // Copy skills to ~/.claude/skills/
    await fs.mkdir(skillsDir, { recursive: true });
    const skillFolders = ['ppg', 'ppg-conductor'];
    let copied = false;

    for (const folder of skillFolders) {
      const srcDir = path.join(srcSkillsDir, folder);
      const destDir = path.join(skillsDir, folder);

      try {
        await fs.access(srcDir);
      } catch {
        continue;
      }

      // Copy recursively (overwrite existing)
      await fs.cp(srcDir, destDir, { recursive: true, force: true });
      copied = true;
    }

    return copied;
  } catch {
    // Non-fatal — skill installation is best-effort
    return false;
  }
}

async function updateGitignore(projectRoot: string): Promise<void> {
  const gitignorePath = path.join(projectRoot, '.gitignore');
  const entriesToAdd = [
    '.pg/results/',
    '.pg/logs/',
    '.pg/manifest.json',
    '.pg/prompts/',
    '.pg/swarms/',
    '.pg/conductor-context.md',
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
