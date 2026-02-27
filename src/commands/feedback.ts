import { execa } from 'execa';
import { output, success, info } from '../lib/output.js';
import { execaEnv } from '../lib/env.js';

const REPO = '2witstudios/ppg-cli';

export interface FeedbackOptions {
  title: string;
  body: string;
  label?: string;
  json?: boolean;
}

async function isGhAvailable(): Promise<boolean> {
  try {
    await execa('gh', ['--version'], execaEnv);
    return true;
  } catch {
    return false;
  }
}

function buildIssueUrl(title: string, body: string, label: string): string {
  const params = new URLSearchParams({ title, body, labels: label });
  return `https://github.com/${REPO}/issues/new?${params.toString()}`;
}

export async function feedbackCommand(options: FeedbackOptions): Promise<void> {
  const { title, body, json = false } = options;
  const label = options.label ?? 'feedback';

  if (await isGhAvailable()) {
    info('Creating GitHub issue via gh CLI');
    const ghArgs = [
      'issue', 'create',
      '--repo', REPO,
      '--title', title,
      '--body', body,
      '--label', label,
    ];

    const result = await execa('gh', ghArgs, execaEnv);
    const issueUrl = result.stdout.trim();

    if (json) {
      output({ success: true, issueUrl, method: 'gh' }, true);
    } else {
      success(`Issue created: ${issueUrl}`);
    }
  } else {
    const issueUrl = buildIssueUrl(title, body, label);
    info('Opening GitHub issue in browser (gh CLI not found)');
    await execa('open', [issueUrl]);

    if (json) {
      output({ success: true, issueUrl, method: 'browser' }, true);
    } else {
      success(`Opened browser: ${issueUrl}`);
    }
  }
}
