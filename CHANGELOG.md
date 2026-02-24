# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-02-24

### Fixed

- Dashboard CI build now uses macOS 26 runner for Liquid Glass support
- npm package renamed to `pure-point-guard` (install: `npm i -g pure-point-guard`)
- Release workflow uses npm Trusted Publishing (OIDC provenance)

## [0.1.0] - 2026-02-23

### Added

- Core orchestration commands: `init`, `spawn`, `status`, `kill`, `merge`
- Agent monitoring: `logs`, `attach`, `wait`, `send`
- Result collection: `aggregate` with file output support
- Worktree management: `worktree create`, `clean`, `diff`
- Agent lifecycle: `restart` for failed/killed agents
- Template system with `{{VAR}}` placeholders and built-in variables
- Agent-agnostic config — works with Claude Code, Codex, or any CLI agent
- Conductor mode — full `--json` support on every command for meta-agent orchestration
- Manifest-based state with file-level locking and atomic writes
- tmux session management: one session per project, one window per worktree, one pane per agent
- Terminal.app auto-open on macOS via AppleScript
- Status detection via signal-stack: result file, pane existence, pane liveness, current command
- Native macOS dashboard app (`ppg ui`)

[0.1.1]: https://github.com/2witstudios/ppg-cli/releases/tag/v0.1.1
[0.1.0]: https://github.com/2witstudios/ppg-cli/releases/tag/v0.1.0
