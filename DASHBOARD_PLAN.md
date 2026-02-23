# ppg dashboard — Native macOS App with SwiftTerm

## Implementation Plan

This document contains everything needed to implement the ppg native dashboard. An agent should follow this file-by-file to produce a working build.

**Project root:** `/Users/jono/Production/ppg-cli`
**Binary name:** `ppg` (defined in `package.json` bin field)
**CLI name:** `ppg` (set in `src/cli.ts` via `program.name('ppg')`)

---

## 1. Existing Xcode Project

An Xcode project already exists at `PPG CLI/` within the repo root. It was created via Xcode as a SwiftUI multiplatform app. Current state:

```
ppg-cli/
├── src/                              # Node.js CLI (modify src/cli.ts, add src/commands/ui.ts)
├── PPG CLI/                          # Existing Xcode project
│   ├── PPG CLI.xcodeproj/
│   │   └── project.pbxproj           # Xcode project config (edit: sandbox, platforms, SwiftTerm dep)
│   ├── PPG CLI/                      # Main app target source
│   │   ├── PPG_CLIApp.swift          # DELETE (SwiftUI @main — replaced by main.swift)
│   │   ├── ContentView.swift         # DELETE (SwiftUI placeholder)
│   │   └── Assets.xcassets/          # App icons, accent color (keep)
│   ├── PPG CLITests/
│   └── PPG CLIUITests/
```

**Key Xcode project settings** (from `project.pbxproj`):
- Bundle identifier: `com.2wit.PPG-CLI`
- Development team: `M96WTV3CKX`
- Deployment targets: macOS 26.1 (multiplatform: iOS, macOS, visionOS)
- Swift version: 5.0
- `ENABLE_APP_SANDBOX = YES` ← **MUST CHANGE TO NO** (see constraints)
- SwiftUI app lifecycle (`@main struct PPG_CLIApp: App`) — **will be replaced with plain `main.swift`**
- Uses `PBXFileSystemSynchronizedRootGroup` — Xcode auto-syncs files in `PPG CLI/` (adding/deleting files in the directory automatically updates the build)

**What the agent needs to do with the Xcode project:**

1. **Add SwiftTerm as a Swift Package dependency** in the Xcode project (via `project.pbxproj` or by instructing the user to add it in Xcode: File → Add Package Dependencies → `https://github.com/migueldeicaza/SwiftTerm.git`, version 1.0.0+)
2. **Disable App Sandbox** — Change `ENABLE_APP_SANDBOX = YES` to `NO` in both Debug and Release build configurations for the "PPG CLI" target
3. **Restrict to macOS only** — Change `SUPPORTED_PLATFORMS` from `"iphoneos iphonesimulator macosx xros xrsimulator"` to `macosx` and remove iOS/visionOS deployment targets
4. **Delete SwiftUI files** — Remove `PPG_CLIApp.swift` and `ContentView.swift` (auto-removed from build by file sync)
5. **Create new Swift source files** in `PPG CLI/PPG CLI/` — `main.swift`, `AppDelegate.swift`, `DashboardSplitViewController.swift`, `SidebarViewController.swift`, `TerminalGridViewController.swift`, `TerminalPane.swift`, `PPGService.swift`, `Models.swift` (auto-included in build by file sync)
6. **Add `PPG CLI/build/` to `.gitignore`** — the `xcodebuild -derivedDataPath build` output directory

---

## 2. File-by-File Implementation

All Swift files go in `PPG CLI/PPG CLI/` (the main app target source directory).

### 2.1 Delete `PPG_CLIApp.swift` and `ContentView.swift`, create `main.swift`

The existing project uses SwiftUI `@main` lifecycle, but we need pure AppKit (NSOutlineView, NSSplitView, SwiftTerm's `LocalProcessTerminalView` are all AppKit). SwiftUI's `@main` creates its own window and fights with manual `NSWindow` creation. The cleanest approach is to **drop SwiftUI entirely**:

1. **Delete** `PPG_CLIApp.swift` (contains `@main struct PPG_CLIApp: App`)
2. **Delete** `ContentView.swift` (SwiftUI placeholder, no longer needed)
3. **Create** `main.swift` — the presence of `main.swift` tells the Swift compiler to use it as the entry point instead of looking for `@main`

Since the project uses `PBXFileSystemSynchronizedRootGroup`, deleting files from `PPG CLI/PPG CLI/` removes them from the build automatically, and creating `main.swift` there adds it automatically.

**`main.swift`** (~30 lines):

```swift
import AppKit

// Parse command-line arguments
var config = LaunchConfig()
let args = CommandLine.arguments
for i in 0..<args.count {
    if args[i] == "--manifest-path", i + 1 < args.count {
        config.manifestPath = args[i + 1]
    }
    if args[i] == "--session-name", i + 1 < args.count {
        config.sessionName = args[i + 1]
    }
}

// Derive project name from manifest path: .pg/manifest.json → parent of .pg/
if !config.manifestPath.isEmpty {
    let url = URL(fileURLWithPath: config.manifestPath)
    config.projectName = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
}

LaunchConfig.shared = config

// Launch NSApplication
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

**`LaunchConfig`** (define in `Models.swift` or `main.swift`):
```swift
struct LaunchConfig {
    static var shared = LaunchConfig()
    var manifestPath: String = ""
    var sessionName: String = ""
    var projectName: String = ""
}
```

### 2.3 New: `AppDelegate.swift` (~80 lines)

`NSObject, NSApplicationDelegate` — creates the main window.

**`applicationDidFinishLaunching(_:)`:**
```
1. Parse CommandLine.arguments:
   - Find --manifest-path, take next arg as path
   - Find --session-name, take next arg as name
   - Store in LaunchConfig.shared
   - Derive projectName from manifest path (go up 2 directories from .pg/manifest.json, take folder name)
2. Create NSWindow:
   - contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800)
   - styleMask: [.titled, .closable, .resizable, .miniaturizable]
   - title: "ppg — {projectName}"
3. window.center()
4. window.contentViewController = DashboardSplitViewController()
5. window.makeKeyAndOrderFront(nil)
6. NSApp.activate(ignoringOtherApps: true)
```

**`applicationShouldTerminateAfterLastWindowClosed(_:)`** → return `true`

### 2.4 New: `DashboardSplitViewController.swift` (~60 lines)

`NSSplitViewController` with sidebar + terminal area.

```
1. let sidebar = SidebarViewController()
2. let terminalGrid = TerminalGridViewController()
3. Wire selection callback:
   sidebar.onSelectionChanged = { [weak self] agents in
       self?.terminalGrid.showAgents(agents)
   }
4. Add split view items:
   - Left: NSSplitViewItem(sidebarWithViewController: sidebar)
     - minimumThickness: 200, maximumThickness: 300
   - Right: NSSplitViewItem(viewController: terminalGrid)
```

### 2.5 New: `SidebarViewController.swift` (~250 lines)

`NSViewController` with `NSOutlineView` showing worktree → agent tree.

**Data model:**
```swift
var worktrees: [WorktreeModel] = []
var onSelectionChanged: (([AgentModel]) -> Void)?
```

**View setup (`loadView`):**
```
1. Create NSScrollView as self.view
2. Create NSOutlineView inside it
   - Single column (NSTableColumn), no header
   - outlineView.headerView = nil
3. Set self as dataSource and delegate
4. Auto-expand worktrees on load
5. Start refresh timer: Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true)
6. Call initial refreshData()
```

**NSOutlineViewDataSource:**
- `numberOfChildrenOfItem:` — nil → worktrees.count, WorktreeModel → agents.count
- `child:ofItem:` — nil → worktrees[index], WorktreeModel → agents[index]
- `isItemExpandable:` — true for WorktreeModel, false for AgentModel

**NSOutlineViewDelegate — `viewFor:item:`:**

For **WorktreeModel**: `NSTableCellView` with:
- Bold text: `worktree.name`
- Secondary: `worktree.branch` + `[worktree.status]`
- SF Symbol icon: `folder.fill`

For **AgentModel**: `NSTableCellView` with:
- Text: `agent.id` + `(agent.agentType)`
- Status circle: SF Symbol `circle.fill` with tint color:
  ```swift
  func statusColor(_ status: AgentStatus) -> NSColor {
      switch status {
      case .running:   return .systemGreen
      case .completed: return .systemBlue
      case .failed:    return .systemRed
      case .killed:    return .systemOrange
      case .lost:      return .systemGray
      case .spawning:  return .systemYellow
      case .waiting:   return .systemGray
      }
  }
  ```

**Selection (`outlineViewSelectionDidChange`):**
```
1. Get selected row/item
2. If WorktreeModel → onSelectionChanged?(worktree.agents)
3. If AgentModel → onSelectionChanged?([agent])
4. If nil → onSelectionChanged?([])
```

**Refresh (`refreshData`):**
```
1. DispatchQueue.global().async {
       let worktrees = PPGService.shared.refreshStatus()
       DispatchQueue.main.async {
           let selectedItem = self.outlineView.item(atRow: self.outlineView.selectedRow)
           self.worktrees = worktrees
           self.outlineView.reloadData()
           // Re-expand all worktrees
           for wt in self.worktrees { self.outlineView.expandItem(wt) }
           // Restore selection if possible
       }
   }
```

### 2.6 New: `TerminalGridViewController.swift` (~200 lines)

Manages one or more `TerminalPane` instances in a vertical split.

**Properties:**
```swift
var currentPanes: [TerminalPane] = []
var splitView: NSSplitView!
var placeholderLabel: NSTextField?
```

**`loadView`:**
```
1. splitView = NSSplitView(frame: .zero)
2. splitView.dividerStyle = .thin
3. splitView.isVertical = false  // stack vertically
4. self.view = splitView
5. Show placeholder: "Select a worktree or agent"
```

**`showAgents(_ agents: [AgentModel])`:**
```
1. Tear down existing panes:
   for pane in currentPanes {
       pane.terminate()
       pane.removeFromSuperview()
   }
   currentPanes.removeAll()
   placeholderLabel?.removeFromSuperview()

2. If agents.isEmpty → show placeholder, return

3. For each agent:
   let pane = TerminalPane(agent: agent, sessionName: LaunchConfig.shared.sessionName)
   splitView.addArrangedSubview(pane)  // or addSubview + constraints
   currentPanes.append(pane)

4. splitView.adjustSubviews()
```

**`deinit`:** terminate all panes.

### 2.7 New: `TerminalPane.swift` (~120 lines)

Wraps SwiftTerm's `LocalProcessTerminalView` for a single tmux pane.

```swift
import SwiftTerm
import AppKit

class TerminalPane: NSView {
    let terminalView: LocalProcessTerminalView
    let agent: AgentModel
    private let labelField: NSTextField

    init(agent: AgentModel, sessionName: String) {
        self.agent = agent
        self.terminalView = LocalProcessTerminalView(frame: .zero)
        self.labelField = NSTextField(labelWithString: "")
        super.init(frame: .zero)

        // Label bar
        labelField.stringValue = "\(agent.id) — \(agent.status.rawValue)"
        labelField.textColor = statusColor(agent.status)
        labelField.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        labelField.backgroundColor = NSColor.windowBackgroundColor
        labelField.drawsBackground = true

        // Layout with Auto Layout
        labelField.translatesAutoresizingMaskIntoConstraints = false
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelField)
        addSubview(terminalView)

        NSLayoutConstraint.activate([
            labelField.topAnchor.constraint(equalTo: topAnchor),
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            labelField.trailingAnchor.constraint(equalTo: trailingAnchor),
            labelField.heightAnchor.constraint(equalToConstant: 22),
            terminalView.topAnchor.constraint(equalTo: labelField.bottomAnchor),
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Start tmux attach
        startTmux(sessionName: sessionName, tmuxTarget: agent.tmuxTarget)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func startTmux(sessionName: String, tmuxTarget: String) {
        // Use shell wrapper because tmux parses ";" as command separator
        // but posix_spawn passes it as a literal arg
        terminalView.startProcess(
            executable: "/bin/zsh",
            args: ["-c", "exec tmux attach-session -t \(sessionName) \\; select-pane -t \(tmuxTarget)"],
            environment: nil,
            execName: "zsh"
        )
    }

    func terminate() {
        terminalView.process?.terminate()
    }
}
```

**Why shell wrapper for tmux:** SwiftTerm's `startProcess` uses `posix_spawn`/`fork+exec`, which passes args literally to the executable — tmux won't interpret `;` as a command separator when received as a separate argv element. Wrapping in `zsh -c "..."` lets the shell parse the compound command correctly.

### 2.8 New: `PPGService.swift` (~150 lines)

Reads `.pg/manifest.json` directly for sidebar data.

```swift
class PPGService {
    static let shared = PPGService()
    var manifestPath: String { LaunchConfig.shared.manifestPath }

    func readManifest() -> ManifestModel? {
        guard let data = FileManager.default.contents(atPath: manifestPath) else { return nil }
        return try? JSONDecoder().decode(ManifestModel.self, from: data)
    }

    func refreshStatus() -> [WorktreeModel] {
        guard let manifest = readManifest() else { return [] }
        return manifest.worktrees.values
            .sorted(by: { $0.createdAt < $1.createdAt })
            .map { entry in
                WorktreeModel(
                    id: entry.id,
                    name: entry.name,
                    branch: entry.branch,
                    status: entry.status,
                    tmuxWindow: entry.tmuxWindow,
                    agents: entry.agents.values
                        .sorted(by: { $0.startedAt < $1.startedAt })
                        .map { AgentModel(from: $0) }
                )
            }
    }
}
```

**Note:** The manifest is kept up-to-date by the ppg Node.js CLI whenever `ppg status` runs (which calls `refreshAllAgentStatuses` in `src/core/agent.ts` and writes back via `updateManifest`). The dashboard reads the file every 2s. Direct file reads are the correct approach — do NOT use `ppg status --json` as its output format (`{ session, worktrees }`) differs from the raw manifest structure and won't parse with `ManifestModel`.

### 2.9 New: `Models.swift` (~80 lines)

**Codable models for parsing `.pg/manifest.json`:**

These must match the TypeScript interfaces in `src/types/manifest.ts` exactly:

```swift
// --- JSON Parsing Models (match manifest.json) ---

struct ManifestModel: Codable {
    let version: Int
    let projectRoot: String
    let sessionName: String
    let worktrees: [String: WorktreeEntryModel]
    let createdAt: String
    let updatedAt: String
}

struct WorktreeEntryModel: Codable {
    let id: String
    let name: String
    let path: String
    let branch: String
    let baseBranch: String
    let status: String       // "active" | "merging" | "merged" | "failed" | "cleaned"
    let tmuxWindow: String
    let agents: [String: AgentEntryModel]
    let createdAt: String
    let mergedAt: String?
}

struct AgentEntryModel: Codable {
    let id: String
    let name: String
    let agentType: String
    let status: String       // "spawning" | "running" | "waiting" | "completed" | "failed" | "killed" | "lost"
    let tmuxTarget: String
    let prompt: String
    let resultFile: String
    let startedAt: String
    let completedAt: String?
    let exitCode: Int?
    let error: String?
}

// --- View Models (used by sidebar/grid) ---

enum AgentStatus: String {
    case spawning, running, waiting, completed, failed, killed, lost
}

// Must be classes (not structs) for NSOutlineView item identity
class WorktreeModel {
    let id: String
    let name: String
    let branch: String
    let status: String
    let tmuxWindow: String
    var agents: [AgentModel]

    init(id: String, name: String, branch: String, status: String, tmuxWindow: String, agents: [AgentModel]) {
        self.id = id; self.name = name; self.branch = branch
        self.status = status; self.tmuxWindow = tmuxWindow; self.agents = agents
    }
}

class AgentModel {
    let id: String
    let name: String
    let agentType: String
    let status: AgentStatus
    let tmuxTarget: String
    let prompt: String
    let startedAt: String

    init(from entry: AgentEntryModel) {
        self.id = entry.id
        self.name = entry.name
        self.agentType = entry.agentType
        self.status = AgentStatus(rawValue: entry.status) ?? .lost
        self.tmuxTarget = entry.tmuxTarget
        self.prompt = entry.prompt
        self.startedAt = entry.startedAt
    }
}
```

**IMPORTANT: Use classes for view models, not structs.** `NSOutlineView` uses object identity (`===`) for item tracking. Structs would break expand/collapse/selection state on reload.

---

## 3. Xcode Project Configuration Changes

These changes must be made in `PPG CLI/PPG CLI.xcodeproj/project.pbxproj`:

### 3.1 Disable App Sandbox

In the target build settings for "PPG CLI" (both Debug and Release), change:
```
ENABLE_APP_SANDBOX = YES  →  ENABLE_APP_SANDBOX = NO
```
This appears in two `XCBuildConfiguration` blocks:
- `FB6FFC262F4C81C800C8D98B` (Debug)
- `FB6FFC272F4C81C800C8D98B` (Release)

Without this, `tmux attach` will fail because the sandbox blocks PTY/process spawning.

### 3.2 Restrict to macOS

In the same two build config blocks, change:
```
SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx xros xrsimulator"  →  SUPPORTED_PLATFORMS = macosx
```

And remove these keys (or leave them, they'll be ignored):
- `IPHONEOS_DEPLOYMENT_TARGET`
- `XROS_DEPLOYMENT_TARGET`
- `TARGETED_DEVICE_FAMILY`

### 3.3 Add SwiftTerm Package Dependency

This requires adding to `project.pbxproj`:
1. A `XCRemoteSwiftPackageReference` section for `https://github.com/migueldeicaza/SwiftTerm.git`
2. A `XCSwiftPackageProductDependency` for `SwiftTerm` in the main target
3. Add the dependency to the target's `packageProductDependencies`

**Alternatively** (recommended for the implementing agent): instruct the user to open the Xcode project and add the package via File → Add Package Dependencies. Editing `project.pbxproj` for SPM packages is error-prone.

---

## 4. CLI Integration

### 4.1 New file: `src/commands/ui.ts`

**Important build context:** Xcode builds to `~/Library/Developer/Xcode/DerivedData/` by default, NOT to a folder inside the source tree. To get a deterministic build output path, `ui.ts` must either:
- Build with `xcodebuild -derivedDataPath` to a known location, or
- Use `open` to launch the .app by bundle ID, or
- Look for the app in `/Applications` or a known install path

The approach below uses `xcodebuild` to build to a local `build/` directory on first run, then launches the built app. Alternatively, the user can build once in Xcode and the command uses `mdfind` (Spotlight) to locate the built `.app`.

```typescript
import path from 'node:path';
import fs from 'node:fs/promises';
import { execa } from 'execa';
import { getRepoRoot } from '../core/worktree.js';
import { readManifest } from '../core/manifest.js';
import { manifestPath } from '../lib/paths.js';
import { NotInitializedError } from '../lib/errors.js';
import { info, warn } from '../lib/output.js';

export async function uiCommand(): Promise<void> {
  const projectRoot = await getRepoRoot();

  let manifest;
  try {
    manifest = await readManifest(projectRoot);
  } catch {
    throw new NotInitializedError(projectRoot);
  }

  const mPath = manifestPath(projectRoot);

  // Find the dashboard app binary
  const appBinary = await findDashboardBinary(projectRoot);
  if (!appBinary) {
    throw new Error(
      'Dashboard app not found. Build it first:\n'
      + '  cd "PPG CLI" && xcodebuild -scheme "PPG CLI" -configuration Release -derivedDataPath build build\n'
      + 'Or open PPG CLI/PPG CLI.xcodeproj in Xcode and build (Cmd+B).'
    );
  }

  info('Launching dashboard...');

  const child = execa(appBinary, [
    '--manifest-path', mPath,
    '--session-name', manifest.sessionName,
  ], {
    stdio: 'ignore',
    detached: true,
  });

  child.unref();
}

async function findDashboardBinary(projectRoot: string): Promise<string | null> {
  // 1. Check local build directory (from xcodebuild -derivedDataPath build)
  const localBuild = path.join(
    projectRoot, 'PPG CLI', 'build', 'Build', 'Products', 'Release',
    'PPG CLI.app', 'Contents', 'MacOS', 'PPG CLI',
  );
  if (await fileExists(localBuild)) return localBuild;

  // 2. Check /Applications
  const appsBuild = '/Applications/PPG CLI.app/Contents/MacOS/PPG CLI';
  if (await fileExists(appsBuild)) return appsBuild;

  // 3. Try Spotlight to find the most recent build
  try {
    const result = await execa('mdfind', [
      'kMDItemCFBundleIdentifier == "com.2wit.PPG-CLI"',
    ]);
    const apps = result.stdout.trim().split('\n').filter(Boolean);
    if (apps.length > 0) {
      const binary = path.join(apps[0], 'Contents', 'MacOS', 'PPG CLI');
      if (await fileExists(binary)) return binary;
    }
  } catch {
    // mdfind not available or no results
  }

  return null;
}

async function fileExists(p: string): Promise<boolean> {
  try { await fs.access(p); return true; } catch { return false; }
}
```

### 4.2 Modify: `src/cli.ts`

Add after the `list` command block (before `program.exitOverride()`):

```typescript
program
  .command('ui')
  .alias('dashboard')
  .description('Open the native dashboard')
  .action(async () => {
    const { uiCommand } = await import('./commands/ui.js');
    await uiCommand();
  });
```

---

## 5. Manifest JSON Reference

The Swift app reads `.pg/manifest.json` directly.

**How session names are computed** (from `src/commands/init.ts:64-65`):
```typescript
const dirName = path.basename(projectRoot);
const sessionName = `ppg-${dirName}`;
```
So for a project at `/Users/jono/Production/my-app`, the session name is `ppg-my-app`. This is stored in the manifest at init time and never changes.

**Example manifest.json** (representative — actual field values vary per project):

```json
{
  "version": 1,
  "projectRoot": "/Users/jono/Production/my-app",
  "sessionName": "ppg-my-app",
  "worktrees": {
    "wt-87e748": {
      "id": "wt-87e748",
      "name": "dash-demo",
      "path": "/Users/jono/Production/my-app/.worktrees/wt-87e748",
      "branch": "ppg/dash-demo",
      "baseBranch": "main",
      "status": "active",
      "tmuxWindow": "ppg-my-app:1",
      "agents": {
        "ag-4he5f1qa": {
          "id": "ag-4he5f1qa",
          "name": "claude",
          "agentType": "claude",
          "status": "running",
          "tmuxTarget": "ppg-my-app:1",
          "prompt": "Explore the current project structure...",
          "resultFile": "/Users/jono/Production/my-app/.pg/results/ag-4he5f1qa.md",
          "startedAt": "2026-02-23T12:11:10.766Z"
        }
      },
      "createdAt": "2026-02-23T12:11:10.767Z"
    }
  },
  "createdAt": "2026-02-23T03:37:41.141Z",
  "updatedAt": "2026-02-23T12:11:10.787Z"
}
```

**Key details:**
- `worktrees` is `Record<string, WorktreeEntry>` (dictionary keyed by worktree ID like `"wt-87e748"`)
- `agents` within each worktree is `Record<string, AgentEntry>` (dictionary keyed by agent ID like `"ag-4he5f1qa"`)
- `sessionName` = `"ppg-{directoryName}"` — computed once at `ppg init` time (see `src/commands/init.ts:65`)
- `tmuxTarget` format: `"sessionName:windowIndex"` (e.g., `"ppg-my-app:1"`)
- Multi-agent worktrees have pane targets: `"ppg-my-app:1.0"`, `"ppg-my-app:1.1"` (window.pane format — the pane ID comes from `tmux split-pane -P -F '#{pane_id}'`, see `src/core/tmux.ts:48-56`)
- Status enums (defined in `src/types/manifest.ts`):
  - **AgentStatus**: `spawning | running | waiting | completed | failed | killed | lost`
  - **WorktreeStatus**: `active | merging | merged | failed | cleaned`

**`ppg status --json` output format differs from manifest.json.** The status command outputs `{ session, worktrees }` (see `src/commands/status.ts:38-43`), NOT the full `Manifest` structure. Do NOT use `ppg status --json` output with the `ManifestModel` decoder — read the manifest file directly instead.

---

## 6. Build & Run

### Build in Xcode (for development):
Open `PPG CLI/PPG CLI.xcodeproj` in Xcode and hit Cmd+B (or Cmd+R to build and run).

### Build from command line (for `ppg ui` integration):
```bash
cd "PPG CLI"
xcodebuild -scheme "PPG CLI" -configuration Release -derivedDataPath build build
```
This builds to a deterministic local path: `PPG CLI/build/Build/Products/Release/PPG CLI.app/`. The `ui.ts` command looks for the binary here first.

### Run directly (after build):
```bash
# From the xcodebuild local build:
"PPG CLI/build/Build/Products/Release/PPG CLI.app/Contents/MacOS/PPG CLI" \
  --manifest-path .pg/manifest.json \
  --session-name ppg-my-app

# From Xcode's DerivedData (path varies):
~/Library/Developer/Xcode/DerivedData/PPG_CLI-*/Build/Products/Release/PPG\ CLI.app/Contents/MacOS/PPG\ CLI \
  --manifest-path .pg/manifest.json \
  --session-name ppg-my-app
```

### Run via CLI (after `ppg ui` is wired up):
```bash
ppg ui
```
The `ui` command auto-discovers the built app via local build path, /Applications, or Spotlight.

---

## 7. Key Constraints & Gotchas

1. **Disable App Sandbox** — Critical. Without this, spawning `tmux` processes will fail silently or with sandbox violations. The Xcode project currently has `ENABLE_APP_SANDBOX = YES` — must be `NO`.

2. **macOS only** — The Xcode project was created as multiplatform (iOS, macOS, visionOS). SwiftTerm's `LocalProcessTerminalView` is macOS-only (AppKit). Restrict to macOS to avoid compilation errors.

3. **NSOutlineView needs classes, not structs** — `NSOutlineView` tracks items by object identity. If you use structs, every `reloadData` will lose expand/selection state because new struct values aren't `===` equal.

4. **SwiftTerm `LocalProcessTerminalView.startProcess`** — This spawns a child process with a PTY. It handles ANSI rendering, resize, scrollback natively. The method signature is: `startProcess(executable:args:environment:execName:)`.

5. **tmux compound commands via shell** — When attaching to a specific pane, use `zsh -c "tmux attach-session -t SESSION \\; select-pane -t TARGET"` rather than passing args directly, because `posix_spawn` won't let tmux parse `;` as its command separator.

6. **Thread safety** — File I/O for manifest reads should happen on a background queue. Dispatch UI updates back to main:
   ```swift
   DispatchQueue.global().async {
       let worktrees = PPGService.shared.refreshStatus()
       DispatchQueue.main.async { self.updateUI(worktrees) }
   }
   ```

7. **Terminal pane lifecycle** — When the sidebar selection changes, terminate old `LocalProcessTerminalView` processes before removing from view hierarchy. This just detaches from tmux — the tmux session itself survives.

8. **File auto-sync** — The Xcode project uses `PBXFileSystemSynchronizedRootGroup`, so any `.swift` files created in `PPG CLI/PPG CLI/` are automatically included in the build, and deleted files are automatically removed. No need to manually edit `project.pbxproj` for source file changes.

9. **Drop SwiftUI entirely** — The existing project uses SwiftUI `@main` lifecycle. Delete `PPG_CLIApp.swift` and `ContentView.swift`, and create `main.swift` instead. The presence of `main.swift` tells the Swift compiler to use it as the entry point (no `@main` attribute needed). This avoids the SwiftUI `@main` lifecycle fighting with manual `NSWindow` creation, and avoids hacks like `Settings { EmptyView() }` or `@NSApplicationDelegateAdaptor`.

10. **Dashboard replaces Terminal.app windows** — Currently, `ppg spawn` auto-opens a Terminal.app window via AppleScript (`src/core/terminal.ts`). The dashboard is the intended replacement for this workflow — it provides a single window with all agents visible in a sidebar, rather than one Terminal.app window per worktree. Users can use `ppg spawn --no-open` to suppress Terminal.app windows when using the dashboard instead.

11. **Add `PPG CLI/build/` to .gitignore** — The `xcodebuild -derivedDataPath build` command creates a `build/` directory inside the Xcode project folder. Add `PPG CLI/build/` to the repo's `.gitignore`.

---

## 8. Verification Checklist

### Build
- [ ] `PPG_CLIApp.swift` and `ContentView.swift` are deleted; `main.swift` exists
- [ ] App sandbox is disabled in both Debug and Release build settings
- [ ] Platform is restricted to macOS only
- [ ] SwiftTerm package dependency resolves and links
- [ ] Xcode project builds without errors (Cmd+B in Xcode)
- [ ] `xcodebuild -scheme "PPG CLI" -configuration Release -derivedDataPath build build` succeeds from `PPG CLI/` directory
- [ ] `PPG CLI/build/` is in `.gitignore`

### Runtime
- [ ] `ppg init` in a test project creates manifest with `sessionName: "ppg-{dirName}"`
- [ ] `ppg spawn --name test --prompt "hello" --no-open` creates a test agent
- [ ] Launch app: `"PPG CLI/build/Build/Products/Release/PPG CLI.app/Contents/MacOS/PPG CLI" --manifest-path .pg/manifest.json --session-name ppg-{dirName}`
- [ ] Window opens with title "ppg — {projectName}"
- [ ] Sidebar shows worktrees from manifest with correct names
- [ ] Expanding a worktree reveals its agents with colored status circles
- [ ] Clicking a worktree shows all its agent terminals in vertical split panes
- [ ] Clicking a single agent shows its terminal full-width
- [ ] Terminal renders ANSI output correctly (colors, cursor movement, 256-color)
- [ ] Resizing the window reflows terminal content instantly, no flicker
- [ ] Typing in a terminal pane sends keystrokes to the tmux pane (interactive)
- [ ] Sidebar refreshes every 2s — new worktrees/agents appear, statuses update
- [ ] `ppg ui` from CLI discovers the built app and launches it
- [ ] Closing the window terminates the dashboard process
