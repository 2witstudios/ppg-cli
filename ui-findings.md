# UI/UX Research Findings

---

## Agent 1: Visual/UX Improvements

*Agent ID: `ag-l0rbfy0u`*

# Result: ag-l0rbfy0u

## Summary
Performed a comprehensive visual/UX review of all 9 Swift source files in the PPG CLI macOS dashboard app. Identified 18 specific improvements across layout, styling, information design, feedback, and interaction quality.

## Changes
No files changed — this is a review/analysis deliverable only.

## Current State Assessment

### What Works Well
- **Clean split-view architecture** — `DashboardSplitViewController` using `NSSplitViewController` with sidebar + content is the right macOS pattern
- **Outline view hierarchy** — The `SidebarNode` wrapper class for NSOutlineView is well-implemented, with proper reference-type semantics
- **Tab management** — `ContentTabViewController` handles tab lifecycle correctly with terminal view caching and proper teardown
- **Status color mapping** — `statusColor(for:)` uses semantic system colors that adapt to light/dark mode
- **Background polling** — 2-second timer with `DispatchQueue.global(qos: .utility)` keeps the UI responsive
- **Session model separation** — `DashboardSession` cleanly separates user-created terminals from manifest agents
- **Context menu pattern** — Right-click rename/delete on terminal entries follows macOS conventions

### What Needs Improvement
The UI currently feels like a functional prototype — all the right pieces exist, but the visual polish, feedback mechanisms, and information density need work to feel like a native macOS app.

---

## Prioritized Improvements

### HIGH IMPACT

#### 1. Add NSToolbar with Standard Window Controls
**File**: `AppDelegate.swift:9-19`
**Problem**: The window has no toolbar, which looks bare for a macOS app. There's no place for common actions like refresh, spawn agent, or toggle sidebar.
**Why**: macOS users expect a toolbar area. It also gives you the unified title-toolbar appearance that modern macOS apps use.
**Implementation**:
```swift
// In AppDelegate.applicationDidFinishLaunching
window.titlebarAppearsTransparent = false
window.toolbarStyle = .unified  // macOS 11+

let toolbar = NSToolbar(identifier: "MainToolbar")
toolbar.delegate = splitVC  // make DashboardSplitViewController the toolbar delegate
toolbar.displayMode = .iconOnly
window.toolbar = toolbar
```
Add toolbar items: sidebar toggle (NSToolbarItem.Identifier.toggleSidebar), flexible space, "New Agent" button (SF Symbol: `plus.circle`), "Refresh" button (SF Symbol: `arrow.clockwise`).

#### 2. Replace NSSegmentedControl Tabs with a Proper Tab Bar
**File**: `ContentTabViewController.swift:24,38`
**Problem**: `NSSegmentedControl` with `.texturedSquare` style is not designed for tab switching. It has no close buttons, no drag reordering, and looks dated. With many agents, labels overflow.
**Why**: Terminal apps (iTerm2, Terminal.app) use a horizontal tab bar that supports overflow, close buttons, and visual selection state.
**Implementation**: Replace with a custom horizontal `NSStackView`-based tab bar where each tab is a custom view:
- Rounded-rect capsule shape for selected tab
- Close button (x) on hover per tab
- Truncation with ellipsis for long labels
- Drag-to-reorder support via `NSDraggingSource`
- Use `NSVisualEffectView` with `.headerView` material for the tab bar background

Alternatively, consider `NSTabView` with `.noTabsNoBorder` style and a custom tab bar, or a `NSCollectionView` with horizontal flow layout for scrollable tabs.

#### 3. Add Visual Feedback for Agent Status in Sidebar
**File**: `SidebarViewController.swift:354-378` (makeAgentCell)
**Problem**: Agents only show a small colored dot and their ID + type. The agent ID (`ag-l0rbfy0u`) is not human-friendly. There's no animation for "running" state and no elapsed time.
**Why**: Users need to quickly scan the sidebar to understand which agents are active and how long they've been running.
**Implementation**:
- Show the agent **name** (from `agent.name`) instead of/in addition to the ID
- Add a pulsing animation on the status dot for `.running` and `.spawning` states:
```swift
if agent.status == .running || agent.status == .spawning {
    let pulse = CABasicAnimation(keyPath: "opacity")
    pulse.fromValue = 1.0
    pulse.toValue = 0.3
    pulse.duration = 1.0
    pulse.autoreverses = true
    pulse.repeatCount = .infinity
    icon.layer?.add(pulse, forKey: "pulse")
    icon.wantsLayer = true
}
```
- Add a secondary label showing elapsed time (e.g., "2m 34s") using a relative date formatter
- Show the first ~40 chars of the prompt as a tooltip: `cell.toolTip = agent.prompt`

#### 4. Sidebar Visual Hierarchy with Source List Style
**File**: `SidebarViewController.swift:92-121`
**Problem**: The sidebar is a basic outline view without macOS source list styling. The "Project" header label at the top with a custom `+` button is non-standard.
**Why**: macOS source lists have built-in vibrancy, selection highlighting, and section header styling. The current approach fights the platform.
**Implementation**:
- Set `outlineView.style = .sourceList` (macOS 11+) — this gives you automatic vibrancy and the correct selection appearance
- Use `outlineView.floatsGroupRows = true` and implement `outlineView(_:isGroupItem:)` returning `true` for the master node to get native section headers
- Remove the custom "Project" header label and move the `+` button into the toolbar
```swift
outlineView.style = .sourceList  // Add to viewDidLoad
// Implement:
func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
    guard let node = item as? SidebarNode else { return false }
    if case .master = node.item { return true }
    return false
}
```

#### 5. Terminal Pane Status Header Bar
**File**: `TerminalPane.swift:21-41`
**Problem**: The status label above the terminal is a plain `NSTextField` with monospaced font. It shows `ag-xxxx — running` with just colored text — no background, no visual weight.
**Why**: This header is the primary signal for "what am I looking at" and needs to be scannable at a glance.
**Implementation**: Replace the plain label with a styled status bar:
```swift
// Create a background bar
let headerBar = NSVisualEffectView()
headerBar.material = .headerView
headerBar.blendingMode = .withinWindow

// Status pill with rounded corners and colored background
let statusPill = NSView()
statusPill.wantsLayer = true
statusPill.layer?.cornerRadius = 4
statusPill.layer?.backgroundColor = statusColor(for: agent.status).withAlphaComponent(0.2).cgColor

// Layout: [icon] Agent Name  [status pill: "running"]  [elapsed time]
```
Add:
- SF Symbol icon (e.g., `cpu` for agent, `terminal` for terminal)
- Agent name prominently, ID in smaller secondary text
- Status pill with colored background + text
- Elapsed time on the right side

---

### MEDIUM IMPACT

#### 6. Window Appearance: Full-Height Sidebar
**File**: `AppDelegate.swift`
**Problem**: The window doesn't use `fullSizeContentView`, so the sidebar doesn't extend to the titlebar like Finder, Xcode, etc.
**Why**: Modern macOS apps use full-height sidebars that blend into the title bar for a cleaner, more immersive look.
**Implementation**:
```swift
window.styleMask.insert(.fullSizeContentView)
window.titlebarAppearsTransparent = true
window.titleVisibility = .hidden
```
Note: When combined with `NSSplitViewController.sidebarWithViewController`, the sidebar automatically extends behind the titlebar with vibrancy.

#### 7. Empty State Design
**File**: `ContentTabViewController.swift:25,48-51`
**Problem**: The placeholder is just a gray text label "Select an item from the sidebar" — no icon, no guidance.
**Why**: Empty states are an opportunity to guide users. A first-time user seeing this has no idea what to do next.
**Implementation**:
```swift
// Replace plain label with a centered stack view
let emptyStack = NSStackView()
emptyStack.orientation = .vertical
emptyStack.alignment = .centerX
emptyStack.spacing = 12

let icon = NSImageView(image: NSImage(systemSymbolName: "rectangle.split.3x1",
    accessibilityDescription: nil)!)
icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 48, weight: .ultraLight)
icon.contentTintColor = .tertiaryLabelColor

let title = NSTextField(labelWithString: "No Agent Selected")
title.font = .systemFont(ofSize: 18, weight: .medium)
title.textColor = .secondaryLabelColor

let subtitle = NSTextField(labelWithString: "Select a worktree or agent from the sidebar,\nor click + to add a new terminal")
subtitle.font = .systemFont(ofSize: 13)
subtitle.textColor = .tertiaryLabelColor
subtitle.alignment = .center
```

#### 8. Worktree Cell — Show Agent Count Badge
**File**: `SidebarViewController.swift:317-352` (makeWorktreeCell)
**Problem**: Worktree cells show name + branch/status but don't indicate how many agents are running inside.
**Why**: Without opening the disclosure triangle, you can't see agent count at a glance.
**Implementation**: Add a trailing badge showing agent count with their aggregate status:
```swift
let badge = NSTextField(labelWithString: "\(worktree.agents.count)")
badge.font = .systemFont(ofSize: 10, weight: .medium)
badge.textColor = .white
badge.alignment = .center
badge.wantsLayer = true
badge.layer?.cornerRadius = 8
badge.layer?.backgroundColor = NSColor.systemGray.cgColor
// Size: 16x16 min
badge.setContentHuggingPriority(.required, for: .horizontal)
```
Color the badge based on worst-status: green if all completed, yellow if any running, red if any failed.

#### 9. Keyboard Shortcuts
**File**: `AppDelegate.swift:23-43`, `SidebarViewController.swift`, `ContentTabViewController.swift`
**Problem**: No keyboard shortcuts beyond the basic Edit menu. No way to switch tabs, navigate sidebar, or create agents with the keyboard.
**Why**: Power users (the target audience for ppg) expect keyboard-driven workflows.
**Implementation**:
- `Cmd+T` — New terminal in current worktree
- `Cmd+Shift+T` — New agent in current worktree
- `Cmd+1..9` — Switch to tab N
- `Cmd+W` — Close current tab
- `Cmd+[` / `Cmd+]` — Previous/next tab
- `Cmd+Shift+[` / `Cmd+Shift+]` — Previous/next sidebar item
- `Cmd+R` — Force refresh sidebar

Add to menu bar and use `NSMenuItem` with `keyEquivalent`.

#### 10. Improve Agent Cell to Show Name, Not Just ID
**File**: `SidebarViewController.swift:365`, `ContentTabViewController.swift:17`
**Problem**: Agent cells display `ag-l0rbfy0u — claude-code` — the ID is meaningless to users. The `AgentModel` has a `.name` field that goes unused.
**Why**: Human-readable names like "fix-auth-bug" are instantly scannable; random IDs are not.
**Implementation**: In `makeAgentCell`:
```swift
// Change from:
let label = NSTextField(labelWithString: "\(agent.id) — \(agent.agentType)")
// To:
let label = NSTextField(labelWithString: agent.name)
label.font = .systemFont(ofSize: 12)
let detail = NSTextField(labelWithString: "\(agent.agentType) · \(agent.id)")
detail.font = .systemFont(ofSize: 10)
detail.textColor = .tertiaryLabelColor
```
Same for `TabEntry.label` — show agent name instead of ID.

#### 11. Dark Terminal Background for Content Area
**File**: `ContentTabViewController.swift:46`
**Problem**: The container view has the default background color, which can create a flash of light background when switching between terminal views.
**Why**: Terminal content is typically dark. The surrounding chrome should not create a jarring contrast.
**Implementation**:
```swift
containerView.wantsLayer = true
containerView.layer?.backgroundColor = NSColor.black.cgColor
```
Or better, use `NSVisualEffectView` with `.dark` appearance for the container.

---

### LOW IMPACT (Polish)

#### 12. Animate Sidebar Refresh
**File**: `SidebarViewController.swift:136-150`
**Problem**: `outlineView.reloadData()` does a full reload, which can cause visual flicker. Selection restoration works but the entire tree jumps.
**Why**: Diffing and animated updates look more polished than hard refreshes.
**Implementation**: Instead of full `reloadData()`, diff the old and new worktree arrays, then use:
```swift
outlineView.beginUpdates()
outlineView.insertItems(at: indexSet, inParent: parent, withAnimation: .slideDown)
outlineView.removeItems(at: indexSet, inParent: parent, withAnimation: .slideUp)
outlineView.endUpdates()
```
This is more complex but eliminates the visual jitter on each 2-second refresh.

#### 13. View Menu — Toggle Sidebar
**File**: `AppDelegate.swift:23-43`
**Problem**: No View menu exists. Users can't toggle the sidebar or enter full screen from the menu.
**Why**: Standard macOS app conventions include a View menu with sidebar toggle and full screen.
**Implementation**:
```swift
let viewMenuItem = NSMenuItem()
let viewMenu = NSMenu(title: "View")
viewMenu.addItem(withTitle: "Toggle Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "s")
    .keyEquivalentModifierMask = [.command, .control]
viewMenu.addItem(NSMenuItem.separator())
viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
    .keyEquivalentModifierMask = [.command, .control]
viewMenuItem.submenu = viewMenu
mainMenu.addItem(viewMenuItem)
```

#### 14. Worktree Status Colors
**File**: `SidebarViewController.swift:324`
**Problem**: Worktree folder icons are all the same default color regardless of worktree status (active, merging, merged, cleaned).
**Why**: Quick visual scanning is hampered when all worktrees look identical.
**Implementation**: Tint the folder icon based on worktree status:
```swift
let folderColor: NSColor = {
    switch worktree.status {
    case "active": return .systemBlue
    case "merging": return .systemYellow
    case "merged": return .systemGreen
    case "cleaned": return .systemGray
    default: return .secondaryLabelColor
    }
}()
icon.contentTintColor = folderColor
```

#### 15. Sidebar Header — Show Session/Project Info
**File**: `SidebarViewController.swift:77-79`
**Problem**: The header shows just "Project" with a `+` button. It could show the project name, session name, and agent count.
**Why**: Context is important when managing multiple ppg projects.
**Implementation**: Show project name prominently, with a subtitle:
```swift
let headerLabel = NSTextField(labelWithString: LaunchConfig.shared.projectName)
headerLabel.font = .systemFont(ofSize: 11, weight: .semibold)
headerLabel.textColor = .secondaryLabelColor

let subtitle = NSTextField(labelWithString: "\(worktrees.count) worktrees · \(totalAgents) agents")
subtitle.font = .systemFont(ofSize: 10)
subtitle.textColor = .tertiaryLabelColor
```

#### 16. Drag-and-Drop Tab Reordering
**File**: `ContentTabViewController.swift`
**Problem**: Tabs are in fixed order (manifest agents first, then session entries). Users can't reorder them.
**Why**: When working with many agents, users want to arrange tabs to match their workflow.
**Implementation**: Moderate effort — requires implementing drag source/destination on the tab bar. Lower priority given the tab bar redesign in item #2 would include this.

#### 17. Confirm Before Closing Window with Running Agents
**File**: `AppDelegate.swift:46-48`
**Problem**: `applicationShouldTerminateAfterLastWindowClosed` returns `true` without checking if agents are running.
**Why**: Accidentally closing the window while agents are running could lose work.
**Implementation**:
```swift
func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let runningAgents = PPGService.shared.refreshStatus()
        .flatMap(\.agents)
        .filter { $0.status == .running }
    if !runningAgents.isEmpty {
        let alert = NSAlert()
        alert.messageText = "Agents Still Running"
        alert.informativeText = "\(runningAgents.count) agent(s) are still running. Quit anyway?"
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
    return .terminateNow
}
```

#### 18. Double-Click Sidebar to Rename
**File**: `SidebarViewController.swift`
**Problem**: Renaming requires right-click > Rename. Double-click doesn't do anything special.
**Why**: Double-click-to-rename is a standard macOS interaction (Finder, Xcode navigator).
**Implementation**: Implement `outlineView(_:shouldEdit:)` or handle double-click action to start inline editing for terminal entries.

---

## Priority Order for Implementation

If tackling these in order of visual impact per effort:

1. **#4 Source list style** — One line (`outlineView.style = .sourceList`) for massive visual upgrade
2. **#1 Add NSToolbar** — ~30 lines for proper macOS window chrome
3. **#6 Full-height sidebar** — 3 lines for modern window appearance
4. **#10 Show agent names** — Simple string change, big readability win
5. **#3 Agent status feedback** — Pulsing dots + elapsed time
6. **#5 Terminal status bar** — Better header for the content area
7. **#2 Tab bar redesign** — Biggest effort but biggest UX payoff
8. **#7 Empty state** — Nice polish for first-run experience

## Notes
- All SF Symbol names referenced (`laptopcomputer`, `folder.fill`, `circle.fill`, `terminal.fill`, `plus`, `cpu`, `rectangle.split.3x1`, `arrow.clockwise`, `plus.circle`) are available in macOS 11+ (SF Symbols 2+)
- The app uses SwiftTerm via SPM (confirmed from xcodeproj). SwiftTerm's `LocalProcessTerminalView` handles the actual terminal rendering — the improvements here focus on the chrome around it
- The `@unchecked Sendable` and `nonisolated` markers suggest this was built for Swift 6 concurrency. UI changes should stay on `@MainActor` or use `DispatchQueue.main.async` as the code already does
- The current 2-second polling interval in `SidebarViewController.startRefreshTimer()` is reasonable but the full `reloadData()` call makes it visually noticeable — improvement #12 addresses this



---

## Agent 2: Modern macOS Dashboard Patterns

*Agent ID: `ag-3uwmrzc0`*

# Result: ag-3uwmrzc0

## Summary
Performed a comprehensive audit of all 9 Swift source files in the PPG CLI macOS dashboard app, surveyed modern macOS developer-tool design patterns from Xcode, Tower, Raycast, TablePlus, iTerm2, and others, and produced a gap analysis with ranked feature recommendations.

## Changes
No files changed — this is a research deliverable.

## Notes
See the full report below.

---

# Modern macOS Dashboard Patterns — Gap Analysis & Feature Recommendations

## 1. Current Dashboard Inventory

The PPG CLI dashboard is a native AppKit app with:

| Component | What it does |
|-----------|-------------|
| `main.swift` | Parses CLI args, boots `NSApplication` |
| `AppDelegate.swift` | Creates single window (1400×900), minimal menu bar (Quit, Edit clipboard ops) |
| `DashboardSplitViewController.swift` | `NSSplitViewController` — sidebar (200-300px) + content area |
| `SidebarViewController.swift` | `NSOutlineView` tree: Master → Worktrees → Agents/Terminals. 2-second poll refresh. Context menu (rename/delete) on terminals |
| `ContentTabViewController.swift` | `NSSegmentedControl` tab bar + terminal views per agent/session. Lazy terminal creation, teardown on tab removal |
| `TerminalPane.swift` | SwiftTerm `LocalProcessTerminalView` wrapping `tmux attach-session` |
| `DashboardSession.swift` | In-memory registry of user-spawned agents and terminals (not persisted) |
| `PPGService.swift` | Reads `manifest.json` from disk, returns `[WorktreeModel]` |
| `Models.swift` | Codable manifest structs, view-model classes, `LaunchConfig` arg parser |

**What works well**: Sidebar + content split, live manifest polling, embedded terminal via SwiftTerm, worktree→agent tree hierarchy, context menus for rename/delete.

---

## 2. Survey of Modern macOS Developer-Tool Patterns

### Xcode (Organizer, Debug Navigator, Build Log)
- **Activity indicator** in toolbar showing build/test progress
- **Filter bar** at bottom of navigator with search + scope buttons
- **Inspector panel** (right sidebar) for detail without navigation
- **Source editor tabs** with pinning, history, close buttons per tab
- **Structured log view** with expandable build phases and timing
- **Notification banners** for build success/failure

### Tower (Git Client)
- **Multi-repo sidebar** with activity badges (uncommitted, ahead/behind)
- **Toolbar actions** (pull, push, stash, branch) always visible
- **Detail inspector** for selected item — diff, commit info, branch status
- **Quick Open** (`Cmd+T`) for switching repos/branches
- **Drag-to-reorder** sidebar items

### Raycast
- **Command palette** (`Cmd+K` or global hotkey) with fuzzy search
- **Keyboard-first navigation** — arrow keys, enter to act, esc to dismiss
- **Extensions/actions** attached to each item
- **Floating window** that doesn't steal focus

### TablePlus
- **Tab bar** with colored connection indicators
- **Connection status badges** (connected/disconnected/error)
- **Quick filter** (`Cmd+F`) that narrows visible items
- **Favorites / pinned items**
- **Multi-pane split** for comparing data side by side

### iTerm2
- **Profile system** for terminal presets
- **Session titles** auto-updating from running process
- **Split panes** (horizontal + vertical) within a single tab
- **Broadcast input** to multiple panes simultaneously
- **Toolbelt** sidebar with jobs, profiles, paste history
- **Triggers** — regex-based actions on terminal output (highlight, alert, silence)
- **Marks** — navigate between command outputs with Cmd+Shift+Up/Down
- **Badge** overlay text on terminal panes
- **Shell integration** for command status detection
- **Hotkey window** — system-wide shortcut to toggle visibility

---

## 3. Gap Analysis — What the Current Dashboard Lacks

### 3.1 Keyboard Navigation & Shortcuts
**Current**: Only `Cmd+Q` and clipboard shortcuts. No way to switch tabs, navigate sidebar, spawn agents, or perform actions via keyboard.
**Gap**: Power developers expect full keyboard-driven workflows.

### 3.2 Command Palette / Quick Actions
**Current**: None. All actions require mouse clicks on sidebar context menus or the `+` button.
**Gap**: No fast way to find/switch-to an agent, trigger actions (kill, merge, aggregate), or run ppg commands from within the dashboard.

### 3.3 Toolbar with Quick Actions
**Current**: Window has no toolbar. The only action button is the `+` in the sidebar header.
**Gap**: Common ppg actions (spawn agent, kill agent, merge worktree, aggregate results) should be one click away.

### 3.4 Agent Status Notifications
**Current**: Status only visible when looking at the sidebar. No notification when an agent completes or fails.
**Gap**: If you're in another app, you have no idea your agent finished. macOS `UserNotifications` integration is missing.

### 3.5 Menu Bar Status Item
**Current**: App is a standard windowed app only.
**Gap**: A menu bar icon showing running agent count / progress would let developers monitor without switching to the dashboard. Think Docker Desktop's whale or Xcode's build indicator.

### 3.6 Agent Output Search/Filtering
**Current**: Terminal output is raw SwiftTerm. No search, no filtering, no scrollback markers.
**Gap**: iTerm2-style `Cmd+F` search within terminal output, and ability to filter sidebar agents by status (running/completed/failed).

### 3.7 Status Bar / Activity Summary
**Current**: No summary view. You must count agents visually in the sidebar.
**Gap**: A bottom bar or toolbar badge showing "3 running, 1 completed, 1 failed" at a glance.

### 3.8 Inspector / Detail Panel
**Current**: Clicking an agent shows its terminal. No metadata view (prompt, start time, worktree path, branch, exit code).
**Gap**: An inspector panel (or popover) showing agent details without switching to the terminal would reduce cognitive load.

### 3.9 Result File Preview / Quick Look
**Current**: No way to view result files from within the dashboard.
**Gap**: When an agent completes, its result `.md` file should be previewable inline — either via Quick Look (`QLPreviewPanel`) or a rendered markdown view.

### 3.10 Proper Tab Bar (Not Segmented Control)
**Current**: `NSSegmentedControl` for tabs — no close buttons, no reordering, no overflow handling.
**Gap**: A proper tab bar (like Xcode/Safari) with close buttons, drag-to-reorder, and overflow menu for many tabs.

### 3.11 Persisted Session State
**Current**: `DashboardSession` is in-memory only. Restarting the app loses all user-spawned agents/terminals.
**Gap**: Session should persist across app restarts (at minimum the tab layout and terminal entries).

### 3.12 Agent Timeline / History View
**Current**: Only live state. No history of past agents, their durations, or outcomes.
**Gap**: A timeline view (like Xcode's build history or CI dashboards) showing agent runs over time with duration bars and status colors.

### 3.13 Split Terminal View
**Current**: One terminal per tab, no side-by-side.
**Gap**: iTerm2-style split panes would let you watch two agents simultaneously.

### 3.14 Broadcast Input
**Current**: Each terminal is independent.
**Gap**: Ability to send the same input to multiple agent terminals simultaneously (useful for debugging or sending Ctrl+C to all).

### 3.15 Window Tab Support
**Current**: Single window.
**Gap**: macOS window tabs (`NSWindow.allowsAutomaticWindowTabbing`) would let users have multiple dashboard windows merged into tabs.

### 3.16 Dark/Light Mode Awareness
**Current**: Uses system colors (`secondaryLabelColor`, etc.) which is good. SwiftTerm terminal theme may not adapt.
**Gap**: Terminal theme should match system appearance and allow customization.

### 3.17 Drag & Drop
**Current**: Sidebar items are static.
**Gap**: Drag to reorder worktrees/agents, drag a terminal from one worktree to another.

### 3.18 View Menu / Appearance Options
**Current**: Only App and Edit menus.
**Gap**: View menu for toggle sidebar, Window menu for standard window management, Agent menu for spawn/kill/merge actions.

---

## 4. Feature Recommendations — Ranked by Developer Impact

### Tier 1: High Impact, Should Ship in v1

| # | Feature | Impact | Complexity | Rationale |
|---|---------|--------|------------|-----------|
| 1 | **Keyboard shortcuts** | Very High | Easy | `Cmd+1-9` for tabs, `Cmd+N` new agent, `Cmd+W` close tab, `Cmd+Shift+N` new terminal, arrow keys in sidebar. ~50 lines in `AppDelegate` menu setup |
| 2 | **macOS notifications** | Very High | Easy | `UNUserNotificationCenter.add()` when agent status changes to `completed` or `failed`. ~30 lines in `PPGService`/sidebar refresh diff detection |
| 3 | **Toolbar with actions** | High | Easy | `NSToolbar` with Spawn, Kill, Merge, Aggregate buttons. Standard macOS pattern. ~100 lines in `AppDelegate` |
| 4 | **Status bar / summary** | High | Easy | Bottom bar or toolbar subtitle: "3 running · 1 completed · 1 failed". Count from `worktrees` array in sidebar. ~40 lines |
| 5 | **Terminal search** | High | Medium | SwiftTerm supports `getTerminal().search()`. Wire up `Cmd+F` to show a search bar above the terminal. ~100 lines |
| 6 | **Agent detail inspector** | High | Medium | `Cmd+I` or click on info button to show a popover/panel with agent metadata (prompt, timing, status, worktree, result file path). ~150 lines |
| 7 | **Sidebar filter by status** | High | Easy | Scope bar or filter tokens below the "Project" header. Filter agents by running/completed/failed. ~60 lines |
| 8 | **Proper tab bar** | Medium | Medium | Replace `NSSegmentedControl` with a custom tab bar or `NSTabView` with close buttons and drag reorder. ~200 lines |

### Tier 2: Medium Impact, Should Ship Soon After v1

| # | Feature | Impact | Complexity | Rationale |
|---|---------|--------|------------|-----------|
| 9 | **Command palette** | High | Medium | `Cmd+K` floating search over all agents, worktrees, and actions. Fuzzy match. ~300 lines (custom `NSPanel` + table) |
| 10 | **Result file preview** | High | Medium | When agent completes, add "View Result" button or auto-show a markdown preview pane. Use `NSAttributedString` or `WKWebView` with markdown-to-HTML. ~200 lines |
| 11 | **Menu bar status item** | Medium | Medium | `NSStatusItem` with agent count badge. Click to show mini-status or bring dashboard to front. ~150 lines |
| 12 | **Full menu bar** | Medium | Easy | Add View, Agent, Window menus with standard items (Toggle Sidebar, Minimize, Zoom, Bring All to Front). ~80 lines |
| 13 | **Persisted session state** | Medium | Medium | Save `DashboardSession.entries` to a JSON file in `.pg/`. Restore on launch. ~100 lines |
| 14 | **Window tabs** | Low | Easy | Set `window.tabbingMode = .preferred`. One line of code for OS-level window tabbing. |

### Tier 3: Nice to Have, Post-v1

| # | Feature | Impact | Complexity | Rationale |
|---|---------|--------|------------|-----------|
| 15 | **Agent timeline/history** | Medium | Hard | Visual timeline with duration bars, requires persisting historical data beyond current manifest. ~500+ lines |
| 16 | **Split terminal view** | Medium | Hard | Horizontal/vertical splits within content area. Requires reworking content layout. ~400 lines |
| 17 | **Broadcast input** | Low | Medium | Send keystrokes to multiple terminals. SwiftTerm would need input forwarding. ~150 lines |
| 18 | **Drag & drop reorder** | Low | Medium | `NSOutlineView` drag/drop data source methods. ~200 lines |
| 19 | **Terminal themes** | Low | Medium | SwiftTerm color scheme configuration matching system appearance. ~100 lines |
| 20 | **Touch Bar** | Very Low | Medium | Deprecated by Apple (no longer on new Macs). Skip entirely. |

---

## 5. Quick Wins — Implement in Under 30 Minutes Each

1. **`Cmd+1` through `Cmd+9`** to switch tabs — add key equivalents in the Edit or new Navigation menu
2. **`Cmd+N`** to spawn new agent — menu item wired to existing `addAgent()` flow
3. **`Cmd+W`** to close current tab — menu item wired to existing `removeTab()` flow
4. **Window tab support** — single line: `window.tabbingMode = .preferred`
5. **Notification on agent completion** — diff agent statuses between refresh cycles, fire `UNUserNotificationCenter` for transitions to `completed`/`failed`
6. **Status summary in window subtitle** — `window.subtitle = "3 running · 1 completed"` (macOS 11+)

---

## 6. Architecture Recommendations

### For Command Palette
Use a floating `NSPanel` (non-activating) with an `NSSearchField` and `NSTableView`. Filter over a flat list of all agents, worktrees, and available actions. Pattern: same architecture as Raycast and Spotlight.

### For Notifications
Detect status transitions by comparing previous and current `AgentStatus` values during the 2-second refresh cycle in `SidebarViewController.refresh()`. Fire notifications only on transitions (not on every poll).

### For Menu Bar Item
Create an `NSStatusItem` in `AppDelegate.applicationDidFinishLaunching`. Update its title/image on the same 2-second refresh cycle. This can coexist with the main window.

### For Result Preview
Add a third split view item (inspector) to `DashboardSplitViewController`, or use `QLPreviewPanel` for Quick Look integration. The result file path is already in the `AgentEntryModel.resultFile` field.

---

## 7. Priority Summary

**v1 must-haves** (features 1-7): Keyboard shortcuts, notifications, toolbar, status bar, terminal search, agent detail inspector, sidebar filtering. These bring the app from "functional prototype" to "daily-driver developer tool."

**Fast-follow** (features 8-14): Command palette, result preview, menu bar item, full menus, session persistence, window tabs. These elevate it to a polished macOS citizen.

**Post-v1** (features 15-20): Timeline, split view, broadcast, drag-drop, themes. These are power-user features that can be driven by real usage feedback.



---

## Agent 3: Accessibility, Keyboard Navigation & Polish

*Agent ID: `ag-abc1682g`*

# Result: ag-abc1682g

## Summary
Completed a thorough audit of the PPG CLI macOS dashboard app (9 Swift source files) for accessibility, keyboard navigation, and polish. Found significant gaps in all three areas — the app is a functional MVP but lacks VoiceOver support, keyboard navigation, Dynamic Type, window restoration, and several polish details.

## Changes
No files changed — this is an audit-only report.

## Notes

---

# PPG CLI Dashboard — Accessibility, Keyboard Navigation & Polish Audit

## 1. Accessibility Audit

### 1.1 VoiceOver Support — FAIL

**No accessibility identifiers or labels are set anywhere in the codebase.**

| Finding | Severity | File / Location |
|---------|----------|-----------------|
| SF Symbol images use `accessibilityDescription: nil` in 4 places | High | `SidebarViewController.swift:299, 324, 361, 398` |
| No `setAccessibilityIdentifier()` on sidebar outline view | High | `SidebarViewController.swift:93-104` |
| No `setAccessibilityLabel()` on sidebar cells (master, worktree, agent, terminal) | High | `SidebarViewController.swift:292-415` |
| No accessibility on segmented control tabs | High | `ContentTabViewController.swift:38-42` |
| No accessibility on "+" add button | Medium | `SidebarViewController.swift:81-85` |
| Placeholder label has no accessibility role | Low | `ContentTabViewController.swift:25,48-51` |
| Status color dot (`circle.fill`) has no textual status description | High | `SidebarViewController.swift:361-362` |
| No accessibility on TerminalPane label | Medium | `TerminalPane.swift:13,22-24` |

**Recommended fixes:**

```swift
// SidebarViewController.swift — makeMasterCell()
let icon = NSImageView(image: NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "Project root")!)

// makeAgentCell()
let icon = NSImageView(image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Status: \(agent.status.rawValue)")!)
cell.setAccessibilityLabel("\(agent.id), \(agent.agentType), status: \(agent.status.rawValue)")

// makeWorktreeCell()
let icon = NSImageView(image: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Worktree")!)
cell.setAccessibilityLabel("\(worktree.name), branch \(worktree.branch), \(worktree.status)")

// makeTerminalEntryCell()
icon = NSImageView(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: entry.kind == .agent ? "Agent" : "Terminal")!)
cell.setAccessibilityLabel(entry.label)

// Add button
addButton.setAccessibilityLabel("Add agent or terminal")

// Outline view
outlineView.setAccessibilityIdentifier("sidebarOutlineView")

// Segmented control
segmentedControl.setAccessibilityIdentifier("contentTabBar")
```

### 1.2 Dynamic Type — FAIL

**All fonts are hardcoded to fixed sizes.** The app uses `boldSystemFont(ofSize: 12)`, `systemFont(ofSize: 13)`, `systemFont(ofSize: 11)`, etc. None of these respond to the user's preferred text size in System Settings > Accessibility > Display > Text Size.

| Finding | Severity | File / Location |
|---------|----------|-----------------|
| Header label: `.boldSystemFont(ofSize: 12)` | Medium | `SidebarViewController.swift:78` |
| Master cell name: `.boldSystemFont(ofSize: 13)` | Medium | `SidebarViewController.swift:303` |
| Worktree name: `.boldSystemFont(ofSize: 13)` | Medium | `SidebarViewController.swift:333` |
| Worktree detail: `.systemFont(ofSize: 11)` | Medium | `SidebarViewController.swift:336` |
| Agent label: `.systemFont(ofSize: 12)` | Medium | `SidebarViewController.swift:366` |
| Terminal label: `.systemFont(ofSize: 12)` | Medium | `SidebarViewController.swift:403` |
| Placeholder: `.systemFont(ofSize: 16)` | Low | `ContentTabViewController.swift:48` |
| TerminalPane label: `.monospacedSystemFont(ofSize: 12, ...)` | Low | `TerminalPane.swift:22` |

**Recommended fix:** Use `NSFont.preferredFont(forTextStyle:)` where available (macOS 11+), or at minimum use the system fonts without hardcoded sizes and let the system scale. For AppKit, the pragmatic approach is:
```swift
// Instead of:
name.font = .boldSystemFont(ofSize: 13)
// Use:
name.font = .preferredFont(forTextStyle: .body)  // or .headline, .subheadline, etc.
```

### 1.3 High Contrast Mode — PARTIAL PASS

The app mostly uses semantic system colors (`.secondaryLabelColor`, `.labelColor`, `.systemGreen`, etc.) which auto-adapt in high contrast mode. However:

| Finding | Severity | File / Location |
|---------|----------|-----------------|
| Status colors (green, blue, red, orange, yellow, gray) may not have enough contrast in high-contrast mode | Low | `SidebarViewController.swift:3-12` (statusColor function) |
| The small `circle.fill` icon at 12pt may be hard to see in high contrast | Low | `SidebarViewController.swift:361` |

**Verdict:** Mostly acceptable. The system colors do adapt, but testing with "Increase contrast" enabled in Accessibility settings is recommended.

### 1.4 Reduce Motion — N/A (PASS by default)

The app has **no animations** — no transitions, no animated status indicators, no view animations. This means it trivially passes Reduce Motion compliance, but it also means there are no motion-based visual cues that could enhance the UX.

### 1.5 Color-Only Differentiation — FAIL

**Agent status is communicated solely through color.**

| Finding | Severity | File / Location |
|---------|----------|-----------------|
| `statusColor()` maps status to color with no textual/shape backup | High | `SidebarViewController.swift:3-12` |
| Agent cell shows `circle.fill` tinted by status — no text label for status | High | `SidebarViewController.swift:354-378` |
| Dashboard session agents also just use green `circle.fill` | Medium | `SidebarViewController.swift:389-396` |

**Recommended fix:** Either:
1. Add the status as text next to the icon: `"\(agent.id) — \(agent.agentType) (\(agent.status.rawValue))"`
2. Or use different SF Symbols per status (e.g., `checkmark.circle.fill` for completed, `xmark.circle.fill` for failed, `play.circle.fill` for running)

---

## 2. Keyboard Navigation Audit

### 2.1 Tab / Shift-Tab Focus Traversal — FAIL

**The app does not configure `nextKeyView` chains.** AppKit requires explicit key view loop setup for Tab/Shift-Tab to move between the sidebar, tab bar, and terminal content.

| Finding | Severity | File / Location |
|---------|----------|-----------------|
| No `nextKeyView` set on any view | High | `DashboardSplitViewController.swift` (entire file) |
| No `window.recalculatesKeyViewLoop` set | High | `AppDelegate.swift:9-20` |

**Recommended fix in `AppDelegate.swift`:**
```swift
window.autorecalculatesKeyViewLoop = true
// OR explicitly:
sidebar.outlineView.nextKeyView = content.segmentedControl
content.segmentedControl.nextKeyView = // current terminal view
```

### 2.2 Keyboard Shortcuts — FAIL

**No keyboard shortcuts exist for common actions.** The only keyboard-accessible actions are Cmd+Q (quit) and Edit menu standard shortcuts.

| Missing Shortcut | Impact | Recommended Binding |
|-----------------|--------|---------------------|
| Spawn new agent | High | Cmd+N |
| Spawn new terminal | High | Cmd+T |
| Switch between sidebar and content | High | Cmd+0 (toggle sidebar) or Cmd+1 |
| Kill/delete selected item | Medium | Cmd+Backspace |
| Rename terminal | Medium | Enter (on selected terminal) |
| Next tab | High | Cmd+] or Ctrl+Tab |
| Previous tab | High | Cmd+[ or Ctrl+Shift+Tab |
| Focus terminal | Medium | Cmd+Shift+T |
| Refresh sidebar | Low | Cmd+R |

**Recommended implementation location:** Add a "View" menu and "Window" menu in `AppDelegate.setupMainMenu()` with these shortcuts. For tab switching, override `keyDown(with:)` in `ContentTabViewController` or add menu items.

### 2.3 Sidebar Arrow Key Navigation — PARTIAL PASS

`NSOutlineView` natively supports arrow key navigation (up/down to move, left/right to collapse/expand). This should work automatically. However:

| Finding | Severity | File / Location |
|---------|----------|-----------------|
| Arrow keys work only when outline view is focused — no obvious way to focus it via keyboard | Medium | `SidebarViewController.swift` |
| No first responder management — app doesn't ensure outline view gets initial focus | Medium | `AppDelegate.swift` |

### 2.4 Terminal Pane Keyboard Interaction — PARTIAL PASS

`SwiftTerm`'s `LocalProcessTerminalView` handles keyboard input natively when it's the first responder. The issue is there's no keyboard shortcut to **focus** the terminal pane and no way to return focus to the sidebar.

### 2.5 Focus Ring Styling — NOT IMPLEMENTED

No custom focus ring styling has been applied. AppKit's default focus rings will appear, but they may be inconsistent given the custom cell views in the outline.

---

## 3. Polish Audit

### 3.1 Window Restoration — FAIL (High Impact)

| Finding | Severity | File / Location |
|---------|----------|-----------------|
| No `window.setFrameAutosaveName()` — window size/position not remembered | High | `AppDelegate.swift:9-14` |
| No state restoration identifiers | Medium | `AppDelegate.swift` |

**Fix:**
```swift
// AppDelegate.swift, after creating window:
window.setFrameAutosaveName("PPGMainWindow")
```

### 3.2 Window Title — PASS

The window title is set to `"ppg — \(LaunchConfig.shared.projectName)"` which is clear and informative. No subtitle is set (could show branch or agent count, but not required).

### 3.3 Consistent Margins/Padding — MINOR ISSUES

| Finding | Severity | File / Location |
|---------|----------|-----------------|
| Sidebar header uses leading: 12, trailing: -8 (asymmetric) | Low | `SidebarViewController.swift:113-114` |
| Cell content uses constant 4pt padding on both sides — quite tight | Low | `SidebarViewController.swift:310-312` |
| Segmented control uses 8pt horizontal margin but terminal is edge-to-edge (0pt) — inconsistent | Low | `ContentTabViewController.swift:55-63` |
| TerminalPane label has 8pt leading but 0pt trailing | Low | `TerminalPane.swift:32-33` |

### 3.4 Loading States — FAIL (Medium Impact)

| Finding | Severity | File / Location |
|---------|----------|-----------------|
| No loading indicator when manifest is being read | Medium | `SidebarViewController.swift:137-150` |
| No loading state when terminal is starting up (process launch can take a moment) | Medium | `ContentTabViewController.swift:174-218` |
| If manifest file doesn't exist yet, sidebar is simply empty with no feedback | Medium | `PPGService.swift:8-12` |

**Recommended:** Show a progress spinner or "Loading..." text in the sidebar during the initial data load. Show "Starting process..." in the terminal container while the shell initializes.

### 3.5 Empty States — PARTIAL PASS

| Finding | Severity | File / Location |
|---------|----------|-----------------|
| Content area shows "Select an item from the sidebar" — good | Pass | `ContentTabViewController.swift:25` |
| Sidebar with no worktrees shows only the master node with no children — no hint to the user | Medium | `SidebarViewController.swift:159-182` |
| No empty state message like "No worktrees yet — run `ppg spawn` to get started" | Medium | — |

### 3.6 Error State Presentation — FAIL (Medium Impact)

| Finding | Severity | File / Location |
|---------|----------|-----------------|
| `PPGService.readManifest()` silently returns nil on JSON decode failure | Medium | `PPGService.swift:8-12` |
| No error display if manifest path is invalid or file is corrupted | Medium | `PPGService.swift` |
| No error display if terminal process fails to start | Medium | `ContentTabViewController.swift:186-205` |
| No error display if tmux session doesn't exist | Medium | `TerminalPane.swift:43-50` |

### 3.7 Smooth Resizing — PASS

The layout uses Auto Layout constraints throughout, and `NSSplitViewController` handles sidebar/content resizing natively. The sidebar has min/max thickness set (200-300pt). Terminal views fill their container. This should resize smoothly.

### 3.8 Additional Polish Findings

| Finding | Severity | File / Location |
|---------|----------|-----------------|
| No Window menu (standard macOS apps have Window menu for Minimize, Zoom, Bring All to Front) | Medium | `AppDelegate.swift:23-43` |
| No View menu (no way to toggle sidebar visibility via menu) | Medium | `AppDelegate.swift:23-43` |
| No toolbar — modern macOS apps typically use NSToolbar | Low | `AppDelegate.swift` |
| Timer never stops when window is hidden/miniaturized (wastes CPU) | Low | `SidebarViewController.swift:131` |
| Context menu only works for terminal entries, not for agents (can't kill an agent from context menu) | Medium | `SidebarViewController.swift:441-469` |
| `fatalError()` in outline view data source on unexpected item — should degrade gracefully | Low | `SidebarViewController.swift:265` |
| No double-click handling on sidebar items (e.g., double-click to rename) | Low | `SidebarViewController.swift` |

---

## 4. Priority Summary

### Critical (should fix before shipping)
1. **VoiceOver labels** — Add `accessibilityDescription` to all SF Symbol images and `setAccessibilityLabel()` on all cells
2. **Color-only status** — Add text status label or use distinct icons per status
3. **Window restoration** — Add `setFrameAutosaveName("PPGMainWindow")`
4. **Keyboard shortcuts** — Add Cmd+T (new terminal), Cmd+N (new agent), Ctrl+Tab/Ctrl+Shift+Tab (switch tabs)

### Important (should fix soon)
5. **Key view loop** — Set `window.autorecalculatesKeyViewLoop = true` or wire `nextKeyView` chain
6. **Standard menus** — Add View menu (toggle sidebar), Window menu (Minimize, Zoom)
7. **Error states** — Show user-visible error when manifest is missing/corrupt or process fails to start
8. **Empty state in sidebar** — Show guidance text when no worktrees exist
9. **Loading indicator** — Show spinner during initial manifest load

### Nice to have
10. **Dynamic Type** — Use `preferredFont(forTextStyle:)` instead of hardcoded sizes
11. **Consistent padding** — Normalize margins across sidebar header, cells, and content area
12. **Timer management** — Pause refresh timer when window is not visible
13. **Agent context menu** — Add "Kill Agent" to right-click menu for manifest agents
14. **Toolbar** — Consider adding NSToolbar for a more native macOS feel


