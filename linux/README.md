# PPG Desktop — Native Linux App

Native Linux desktop application for PPG (Pure Point Guard), built with Rust, GTK4, and libadwaita.

## Features

- **Sidebar navigation**: Projects > Worktrees > Agents hierarchy with status badges
- **Terminal panes**: VTE terminals attached to tmux sessions (up to 2×3 grid)
- **Command palette**: Agent variant picker + prompt input (Ctrl+Shift+P)
- **Home dashboard**: Agent stats, git commit heatmap, recent commits
- **Settings**: Terminal font/size, appearance (dark/light/system), server connection
- **Real-time updates**: WebSocket integration with auto-reconnect
- **REST API client**: Connects to `ppg serve` HTTP endpoints

## Prerequisites

### System Dependencies

```bash
# Ubuntu/Debian
sudo apt install \
    build-essential \
    libgtk-4-dev \
    libadwaita-1-dev \
    libvte-2.91-gtk4-dev \
    libcairo2-dev \
    libpango1.0-dev \
    pkg-config

# Fedora
sudo dnf install \
    gtk4-devel \
    libadwaita-devel \
    vte291-gtk4-devel \
    cairo-devel \
    pango-devel

# Arch
sudo pacman -S gtk4 libadwaita vte4 cairo pango
```

### Runtime Dependencies

- **ppg**: `npm install -g ppg-cli`
- **tmux**: `sudo apt install tmux` (or equivalent)
- **Rust 1.78+**: [rustup.rs](https://rustup.rs)

## Build

```bash
cd linux/
cargo build --release
```

The binary will be at `target/release/ppg-desktop`.

## Run

```bash
# Start the PPG server first
ppg serve start --port 3000

# Launch the desktop app
./target/release/ppg-desktop

# Or with options
./target/release/ppg-desktop --url http://localhost:3000 --token mysecret
```

### CLI Options

| Option | Description | Default |
|--------|-------------|---------|
| `--url`, `-u` | PPG server URL | `http://localhost:3000` |
| `--token`, `-t` | Bearer token | None |
| `--help`, `-h` | Show help | — |
| `--version`, `-V` | Show version | — |

## Development

```bash
# Run in debug mode
cargo run -- --url http://localhost:3000

# Check compilation
cargo check

# Run tests
cargo test

# Type checking
cargo clippy
```

## Architecture

```
src/
├── main.rs              # CLI arg parsing, GTK app launch
├── app.rs               # PpgApplication (adw::Application), CSS loading
├── state.rs             # AppState (Arc<RwLock>), Services bundle
├── models/
│   ├── manifest.rs      # Manifest, WorktreeEntry, AgentEntry (serde)
│   ├── agent_variant.rs # Claude, Codex, OpenCode, Terminal variants
│   └── settings.rs      # AppSettings (TOML config)
├── api/
│   ├── client.rs        # PpgClient (reqwest HTTP wrapper)
│   └── websocket.rs     # WsManager (tokio-tungstenite, glib dispatch)
├── ui/
│   ├── window.rs        # MainWindow (NavigationSplitView)
│   ├── sidebar.rs       # SidebarView (ListBox tree)
│   ├── terminal_pane.rs # VTE terminal widget
│   ├── pane_grid.rs     # Terminal grid layout (2×3)
│   ├── home_dashboard.rs # Stats + heatmap + commits
│   ├── command_palette.rs # Agent spawn dialog (Ctrl+Shift+P)
│   ├── worktree_detail.rs # Worktree info panel
│   ├── settings_dialog.rs # PreferencesWindow
│   └── setup_view.rs    # Prerequisites check
└── util/
    └── shell.rs         # Shell escape, tmux commands
```

## VTE Terminal Integration

The terminal pane is designed to use VTE (Virtual Terminal Emulator), the same library used by GNOME Terminal. Each pane attaches to a tmux session to show live agent output.

If the `vte4` crate is not available, the app shows a placeholder with instructions. To enable VTE:

1. Install `libvte-2.91-gtk4-dev`
2. Add the `vte4` crate to `Cargo.toml` when bindings are available
3. Or use the C FFI approach documented in `terminal_pane.rs`

## Settings Storage

Settings are stored in `~/.config/ppg-desktop/settings.toml`:

```toml
server_url = "http://localhost:3000"
font_family = "Monospace"
font_size = 12
appearance = "system"
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Ctrl+Shift+P | Open command palette |
