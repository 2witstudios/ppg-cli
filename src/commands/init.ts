import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execa } from 'execa';
import { ppgDir, resultsDir, logsDir, templatesDir, promptsDir, promptFile, swarmsDir, manifestPath, agentPromptsDir, configPath } from '../lib/paths.js';
import { NotGitRepoError } from '../lib/errors.js';
import { success, info } from '../lib/output.js';
import { loadConfig, writeDefaultConfig } from '../core/config.js';
import { createEmptyManifest, writeManifest } from '../core/manifest.js';
import { bundledPrompts } from '../bundled/prompts.js';
import { bundledSwarms } from '../bundled/swarms.js';
import { execaEnv } from '../lib/env.js';
import { checkTmux, sanitizeTmuxName } from '../core/tmux.js';

const CONDUCTOR_CONTEXT = `# PPG Conductor Context

You are operating on the master branch of a ppg-managed project.

## When to Use ppg
Use \`ppg spawn\` whenever you want work to appear in the **ppg dashboard** — parallel tasks, code reviews,
batch issue work, multi-agent swarms. Agents spawned through ppg run in tmux panes the user can monitor,
interact with, and manage. Available agent types: \`claude\` (default), \`codex\`, \`opencode\` via \`--agent\`.

Direct edits, quick commands, and research are fine to do yourself — not everything needs an agent.
Never run \`claude\`, \`codex\`, or \`opencode\` directly as bash commands — they won't appear in the dashboard.

## Quick Reference
- \`ppg spawn --name <name> --prompt "<task>" --json\` — Spawn worktree + agent
- \`ppg spawn --name <name> --agent codex --prompt "<task>" --json\` — Use Codex agent
- \`ppg spawn --name <name> --agent opencode --prompt "<task>" --json\` — Use OpenCode agent
- \`ppg spawn --worktree <id> --agent codex --prompt "review --base main" --json\` — Codex review
- \`ppg status --json\` — Check statuses
- \`ppg aggregate --all --json\` — Collect results (includes PR URLs)
- \`ppg kill --agent <id> --json\` — Kill agent
- \`ppg reset --json\` — Clean up all worktrees (skips worktrees with open PRs)

## Workflow
1. Break request into parallelizable tasks
2. Spawn: \`ppg spawn --name <name> --prompt "<prompt>" --json\`
3. Poll: \`ppg status --json\` every 5s
4. Aggregate: \`ppg aggregate --all --json\` — result files include PR URLs
5. Present PR links and summaries — let user decide next steps
6. To merge remotely: \`gh pr merge <url> --squash --delete-branch\`
7. To merge locally (power-user): \`ppg merge <wt-id> --json\`
8. Cleanup: \`ppg reset --json\` (skips worktrees with open PRs)

Each agent prompt must be self-contained — agents have no memory of this conversation.
Always use \`--json\`.
`;

const DEFAULT_TEMPLATE = `# Task: {{TASK_NAME}}

## Context
You are working in a git worktree at: {{WORKTREE_PATH}}
Branch: {{BRANCH}}
Project root: {{PROJECT_ROOT}}

## Instructions
{{PROMPT}}
`;

export async function initCommand(options: { json?: boolean }): Promise<void> {
  const cwd = process.cwd();

  // 1. Verify git repo
  let projectRoot: string;
  try {
    const result = await execa('git', ['rev-parse', '--show-toplevel'], { ...execaEnv, cwd });
    projectRoot = result.stdout.trim();
  } catch {
    throw new NotGitRepoError(cwd);
  }

  // 2. Check tmux available
  await checkTmux();

  // 3. Create directories
  const dirs = [
    ppgDir(projectRoot),
    resultsDir(projectRoot),
    logsDir(projectRoot),
    templatesDir(projectRoot),
    promptsDir(projectRoot),
    agentPromptsDir(projectRoot),
    swarmsDir(projectRoot),
  ];

  for (const dir of dirs) {
    await fs.mkdir(dir, { recursive: true });
  }

  info('Created .ppg/ directory structure');

  // 4. Write default config (skip if exists)
  const cfgPath = configPath(projectRoot);
  try {
    await fs.access(cfgPath);
    info('config.yaml already exists, skipping');
  } catch {
    await writeDefaultConfig(projectRoot);
    info('Wrote default config.yaml');
  }

  // 5. Write empty manifest
  // Honor sessionName from config.yaml if user has set a custom value;
  // otherwise derive from directory name. Always sanitize for tmux
  // (dots/colons are session.window.pane separators in tmux targets).
  const config = await loadConfig(projectRoot);
  const dirName = path.basename(projectRoot);
  const rawSessionName = config.sessionName !== 'ppg'
    ? config.sessionName
    : `ppg-${dirName}`;
  const sessionName = sanitizeTmuxName(rawSessionName);
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
  const conductorPath = path.join(ppgDir(projectRoot), 'conductor-context.md');
  await fs.writeFile(conductorPath, CONDUCTOR_CONTEXT, 'utf-8');
  info('Wrote conductor-context.md');

  // 10b. Register project in global registry (for ppg serve)
  const { registerProject } = await import('../core/projects.js');
  await registerProject(projectRoot);
  info('Registered project in global registry');

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
      ppgDir: ppgDir(projectRoot),
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
    '.ppg/results/',
    '.ppg/logs/',
    '.ppg/manifest.json',
    '.ppg/prompts/',
    '.ppg/agent-prompts/',
    '.ppg/swarms/',
    '.ppg/conductor-context.md',
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
