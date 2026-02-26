# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in ppg-cli, please report it responsibly.

**Do not open a public issue.** Instead, email **2witstudios@gmail.com** with:

- A description of the vulnerability
- Steps to reproduce
- Potential impact

You should receive a response within 72 hours. We'll work with you to understand the issue and coordinate a fix before any public disclosure.

## Scope

ppg-cli runs locally and executes shell commands (tmux, git, agent CLIs) on your machine. Security concerns include:

- Command injection via untrusted prompt text or template variables
- Manifest tampering leading to unintended command execution
- File path traversal in worktree or result file operations

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.1.x   | Yes       |
