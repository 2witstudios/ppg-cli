export const bundledSwarms: Record<string, string> = {
  'code-review': `name: code-review
description: Multi-perspective code review
strategy: shared

agents:
  - prompt: review-quality
  - prompt: review-security
  - prompt: review-regression
`,
};
