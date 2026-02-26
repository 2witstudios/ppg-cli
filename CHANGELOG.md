# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-02-25

### Added

- **Command palette for pane creation** — Cmd+N spawns new agents via variant selection and command palette (#30)
- **Agent variants** — multi-agent support with configurable agent types (#30)
- **Tabbed Settings UI** with AppSettingsManager (#28)
- **2x3 grid layout** — pane grid constraints with improved split/close logic
- **Single-pane hover overlay** — quick access controls when hovering over a solo pane
- **`pr` and `reset` commands** — self-awareness module and enhanced cleanup
- **Worktree name normalization** for `--name` values (#29)

### Performance

- **FSEvents file watching** replaces polling for manifest updates — dramatically reduces CPU usage (#21)
- **Incremental sidebar tree updates** instead of full rebuild on every change (#22)
- **Optimized threading** — reduced main-thread contention in dashboard (#23)
- **Optimized terminal rendering and memory** for multi-agent views (#24)
- **Fixed stale sidebar data** when contentSignature is unchanged (#27)

### Fixed

- tmux `send-keys` not submitting Enter to Claude Code agents (#25)
- `spawn`/`restart` opening unwanted Terminal.app windows (#26)
- tmux not found in dashboard TerminalPane and Terminal.app on M-series Macs
- Single-pane hover overlay close button now correctly kills agent

### Changed

- Reduced sidebar status circles and indentation for cleaner look
- Shrunk terminal icon to match agent circle size
- Filtered worktree variant from pane command palette
- Removed agent command setting and General tab from Settings

## [0.1.1] - 2026-02-24

### Fixed

- Dashboard CI build now uses macOS 26 runner for Liquid Glass support
- npm package renamed to `pointguard` (install: `npm i -g pointguard`)
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
- Native macOS dashboard app (`pogu ui`)

[0.2.0]: https://github.com/2witstudios/pogu-cli/releases/tag/v0.2.0
[0.1.1]: https://github.com/2witstudios/pogu-cli/releases/tag/v0.1.1
[0.1.0]: https://github.com/2witstudios/pogu-cli/releases/tag/v0.1.0
