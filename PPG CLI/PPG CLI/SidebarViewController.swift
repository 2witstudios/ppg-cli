import AppKit

/// Chrome background — semi-transparent dark to let desktop show through.
let chromeBackground = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 0.7)

/// Terminal background — opaque dark to match tmux.
let terminalBackground = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)

/// Terminal foreground text — light on dark.
let terminalForeground = NSColor(srgbRed: 0.85, green: 0.85, blue: 0.87, alpha: 1.0)

func statusColor(for status: AgentStatus) -> NSColor {
    switch status {
    case .running: return .systemGreen
    case .completed: return .systemBlue
    case .failed: return .systemRed
    case .killed: return .systemOrange
    case .lost, .waiting: return .systemGray
    case .spawning: return .systemYellow
    }
}

// MARK: - Sidebar Tab

enum SidebarTab {
    case dashboard, swarms, prompts
}

// MARK: - Sidebar Item

enum SidebarItem {
    case project(ProjectContext)
    case worktree(WorktreeModel)
    case agent(AgentModel)
    case agentGroup([AgentModel], String)   // agents sharing a window, window key
    case terminal(DashboardSession.TerminalEntry)

    var id: String {
        switch self {
        case .project(let ctx): return "project-\(ctx.projectRoot.hashValue)"
        case .worktree(let wt): return wt.id
        case .agent(let ag): return ag.id
        case .agentGroup(_, let windowKey): return "group-\(windowKey)"
        case .terminal(let te): return te.id
        }
    }

    /// Signature capturing mutable display-relevant fields.
    /// When this changes for the same `id`, the cell needs a visual refresh.
    var contentSignature: String {
        switch self {
        case .project(let ctx):
            let idx = OpenProjects.shared.indexOf(root: ctx.projectRoot) ?? -1
            return "\(ctx.projectName)|\(idx)"
        case .worktree(let wt):
            return "\(wt.name)|\(wt.branch)|\(wt.status)|\(wt.agents.count)"
        case .agent(let ag):
            return "\(ag.name)|\(ag.agentType)|\(ag.status.rawValue)"
        case .agentGroup(let agents, _):
            return agents.map { "\($0.id):\($0.status.rawValue)" }.joined(separator: ",")
        case .terminal(let te):
            return "\(te.label)|\(te.kind.rawValue)"
        }
    }
}

// Wrapper class for use as NSOutlineView item (requires reference type identity)
class SidebarNode {
    var item: SidebarItem
    var children: [SidebarNode] = []

    init(_ item: SidebarItem) {
        self.item = item
    }
}

//// Holds a (ProjectContext, worktreeId) pair for NSMenuItem.representedObject.
private class WorktreeMenuRef: NSObject {
    let ctx: ProjectContext
    let worktreeId: String
    init(ctx: ProjectContext, worktreeId: String) {
        self.ctx = ctx
        self.worktreeId = worktreeId
    }
}

// MARK: - SidebarViewController

class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    let scrollView = NSScrollView()
    let outlineView = NSOutlineView()

    var projectWorktrees: [String: [WorktreeModel]] = [:]

    var onItemSelected: ((SidebarItem) -> Void)?
    var onAddAgent: ((ProjectContext, String?) -> Void)?
    var onAddTerminal: ((ProjectContext, String?) -> Void)?
    var onAddWorktree: ((ProjectContext) -> Void)?
    var onRenameTerminal: ((ProjectContext, String, String) -> Void)?   // (project, id, newLabel)
    var onDeleteTerminal: ((ProjectContext, String) -> Void)?            // (project, id)
    var onRenameAgent: ((ProjectContext, String, String) -> Void)?       // (project, agentId, newName)
    var onDeleteAgent: ((ProjectContext, String) -> Void)?               // (project, agentId)
    var onDeleteWorktree: ((ProjectContext, String) -> Void)?            // (project, worktreeId)
    var onDataRefreshed: ((SidebarItem?) -> Void)?
    var onSettingsClicked: (() -> Void)?
    var onAddProject: (() -> Void)?
    var onDashboardClicked: (() -> Void)?
    var onSwarmsClicked: (() -> Void)?
    var onPromptsClicked: (() -> Void)?

    private var safetyTimer: Timer?
    private var settingsObserver: NSObjectProtocol?
    private var manifestWatchers: [String: ManifestWatcher] = [:]  // projectRoot -> watcher
    private var debounceWorkItem: DispatchWorkItem?
    /// Prevents overlapping background refreshes from piling up.
    private var isRefreshing = false
    private(set) var activeTab: SidebarTab?
    var isDashboardSelected: Bool { activeTab == .dashboard }
    private var dashboardRow: SidebarNavRow!
    private var swarmsRow: SidebarNavRow!
    private var promptsRow: SidebarNavRow!
    var projectNodes: [SidebarNode] = []
    private var suppressSelectionCallback = false
    private var contextClickedNode: SidebarNode?

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Outline view — pinned directly to top safe area (no header bar)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.title = ""
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.rowSizeStyle = .medium
        outlineView.style = .sourceList
        outlineView.indentationPerLevel = 10

        let contextMenu = NSMenu()
        contextMenu.delegate = self
        outlineView.menu = contextMenu

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        outlineView.backgroundColor = .clear
        view.addSubview(scrollView)

        // Navigation rows (Slack/Notion style)
        let navBar = NSView()
        navBar.translatesAutoresizingMaskIntoConstraints = false

        dashboardRow = SidebarNavRow(title: "Dashboard", icon: "square.grid.2x2") { [weak self] in
            self?.dashboardButtonClicked()
        }
        swarmsRow = SidebarNavRow(title: "Swarms", icon: "arrow.triangle.swap") { [weak self] in
            self?.swarmsButtonClicked()
        }
        promptsRow = SidebarNavRow(title: "Prompts", icon: "doc.text") { [weak self] in
            self?.promptsButtonClicked()
        }

        let navStack = NSStackView(views: [dashboardRow, swarmsRow, promptsRow])
        navStack.orientation = .vertical
        navStack.alignment = .leading
        navStack.spacing = 2
        navStack.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(navStack)

        let dashSeparator = NSBox()
        dashSeparator.boxType = .separator
        dashSeparator.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(dashSeparator)

        view.addSubview(navBar)

        NSLayoutConstraint.activate([
            navBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),

            navStack.topAnchor.constraint(equalTo: navBar.topAnchor, constant: 6),
            navStack.leadingAnchor.constraint(equalTo: navBar.leadingAnchor, constant: 8),
            navStack.trailingAnchor.constraint(equalTo: navBar.trailingAnchor, constant: -8),
            navStack.bottomAnchor.constraint(equalTo: dashSeparator.topAnchor, constant: -6),

            dashboardRow.widthAnchor.constraint(equalTo: navStack.widthAnchor),
            swarmsRow.widthAnchor.constraint(equalTo: navStack.widthAnchor),
            promptsRow.widthAnchor.constraint(equalTo: navStack.widthAnchor),

            dashSeparator.bottomAnchor.constraint(equalTo: navBar.bottomAnchor),
            dashSeparator.leadingAnchor.constraint(equalTo: navBar.leadingAnchor),
            dashSeparator.trailingAnchor.constraint(equalTo: navBar.trailingAnchor),
        ])

        // Footer bar
        let footerBar = NSView()
        footerBar.wantsLayer = true
        footerBar.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        footerBar.addSubview(separator)

        let gearButton = NSButton()
        gearButton.bezelStyle = .accessoryBarAction
        gearButton.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "Settings")
        gearButton.isBordered = false
        gearButton.contentTintColor = terminalForeground
        gearButton.target = self
        gearButton.action = #selector(settingsButtonClicked)
        gearButton.translatesAutoresizingMaskIntoConstraints = false
        footerBar.addSubview(gearButton)

        let addProjectButton = NSButton()
        addProjectButton.bezelStyle = .accessoryBarAction
        addProjectButton.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "Add Project")
        addProjectButton.title = "Add Project"
        addProjectButton.imagePosition = .imageLeading
        addProjectButton.font = .systemFont(ofSize: 11)
        addProjectButton.isBordered = false
        addProjectButton.contentTintColor = terminalForeground
        addProjectButton.target = self
        addProjectButton.action = #selector(addProjectButtonClicked)
        addProjectButton.translatesAutoresizingMaskIntoConstraints = false
        footerBar.addSubview(addProjectButton)

        let shortcutLabel = NSTextField(labelWithString: "\u{2318}O")
        shortcutLabel.font = .systemFont(ofSize: 10)
        shortcutLabel.textColor = .tertiaryLabelColor
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        footerBar.addSubview(shortcutLabel)

        view.addSubview(footerBar)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: navBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerBar.topAnchor),

            footerBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            footerBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            footerBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footerBar.heightAnchor.constraint(equalToConstant: 36),

            separator.topAnchor.constraint(equalTo: footerBar.topAnchor),
            separator.leadingAnchor.constraint(equalTo: footerBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: footerBar.trailingAnchor),

            gearButton.leadingAnchor.constraint(equalTo: footerBar.leadingAnchor, constant: 8),
            gearButton.centerYAnchor.constraint(equalTo: footerBar.centerYAnchor),

            addProjectButton.trailingAnchor.constraint(equalTo: shortcutLabel.leadingAnchor, constant: -4),
            addProjectButton.centerYAnchor.constraint(equalTo: footerBar.centerYAnchor),

            shortcutLabel.trailingAnchor.constraint(equalTo: footerBar.trailingAnchor, constant: -10),
            shortcutLabel.centerYAnchor.constraint(equalTo: footerBar.centerYAnchor),
        ])

        startRefreshTimer()
    }

    func selectTab(_ tab: SidebarTab) {
        activeTab = tab
        dashboardRow.isSelected = (tab == .dashboard)
        swarmsRow.isSelected = (tab == .swarms)
        promptsRow.isSelected = (tab == .prompts)
    }

    private func deselectAllTabs() {
        activeTab = nil
        dashboardRow.isSelected = false
        swarmsRow.isSelected = false
        promptsRow.isSelected = false
    }

    private func dashboardButtonClicked() {
        outlineView.deselectAll(nil)
        selectTab(.dashboard)
        onDashboardClicked?()
    }

    private func swarmsButtonClicked() {
        outlineView.deselectAll(nil)
        selectTab(.swarms)
        onSwarmsClicked?()
    }

    private func promptsButtonClicked() {
        outlineView.deselectAll(nil)
        selectTab(.prompts)
        onPromptsClicked?()
    }

    @objc private func settingsButtonClicked() {
        onSettingsClicked?()
    }

    @objc private func addProjectButtonClicked() {
        onAddProject?()
    }

    // MARK: - Refresh

    /// Whether the very first load has happened (uses full reloadData).
    private var hasPerformedInitialLoad = false

    private func startRefreshTimer() {
        refresh()
        syncManifestWatchers()
        scheduleSafetyTimer()

        // Restart safety timer when refresh interval changes
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .appSettingsDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            guard let key = notification.userInfo?[AppSettingsManager.changedKeyUserInfoKey] as? AppSettingsKey,
                  key == .refreshInterval else { return }
            self?.scheduleSafetyTimer()
        }
    }

    private func scheduleSafetyTimer() {
        safetyTimer?.invalidate()
        safetyTimer = Timer.scheduledTimer(withTimeInterval: AppSettingsManager.shared.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
            self?.syncManifestWatchers()
        }
    }

    /// Ensure we have a file watcher for every open project's manifest, and remove stale ones.
    /// Also retries any watchers that failed to open their file (e.g. manifest didn't exist yet).
    private func syncManifestWatchers() {
        let currentRoots = Set(OpenProjects.shared.projects.map(\.projectRoot))
        let watchedRoots = Set(manifestWatchers.keys)

        // Stop watchers for removed projects
        for root in watchedRoots.subtracting(currentRoots) {
            manifestWatchers[root]?.stop()
            manifestWatchers.removeValue(forKey: root)
        }

        // Start watchers for new projects
        for root in currentRoots.subtracting(watchedRoots) {
            let pgDir = (root as NSString).appendingPathComponent(".pg")
            let manifestPath = (pgDir as NSString).appendingPathComponent("manifest.json")
            let watcher = ManifestWatcher(path: manifestPath) { [weak self] in
                self?.scheduleDebounceRefresh()
            }
            manifestWatchers[root] = watcher
        }

        // Retry watchers that failed to open (manifest didn't exist at creation time)
        for (_, watcher) in manifestWatchers where !watcher.isWatching {
            watcher.retry()
        }
    }

    /// Debounce rapid file changes — coalesce into a single refresh after 300ms of quiet.
    private func scheduleDebounceRefresh() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refresh()
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    func refresh() {
        // Skip if a background refresh is already in flight — avoids piling up work
        guard !isRefreshing else { return }
        isRefreshing = true

        let openProjects = OpenProjects.shared.projects

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var results: [String: [WorktreeModel]] = [:]

            for ctx in openProjects {
                let worktrees = PPGService.shared.refreshStatus(manifestPath: ctx.manifestPath)
                results[ctx.projectRoot] = worktrees
            }

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRefreshing = false

                self.projectWorktrees = results
                let newTree = self.buildTree()

                if !self.hasPerformedInitialLoad {
                    // First load — full reload
                    self.projectNodes = newTree
                    self.outlineView.reloadData()
                    self.expandAll()
                    self.hasPerformedInitialLoad = true
                } else {
                    // Incremental diff
                    self.suppressSelectionCallback = true
                    self.applyTreeDiff(from: self.projectNodes, to: newTree)
                    self.suppressSelectionCallback = false
                }

                let currentItem = self.currentSelectedItem()
                self.onDataRefreshed?(currentItem)
            }
        }
    }

    func currentSelectedItem() -> SidebarItem? {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? SidebarNode else { return nil }
        return node.item
    }

    /// Build a fresh tree from current data without mutating `projectNodes`.
    private func buildTree() -> [SidebarNode] {
        var result: [SidebarNode] = []

        for ctx in OpenProjects.shared.projects {
            let projectNode = SidebarNode(.project(ctx))

            // Master-level dashboard entries (agents + terminals without a parent worktree)
            for entry in ctx.dashboardSession.entriesForMaster() {
                projectNode.children.append(SidebarNode(.terminal(entry)))
            }

            // Worktrees from manifest
            let worktrees = projectWorktrees[ctx.projectRoot] ?? []
            for wt in worktrees {
                let wtNode = SidebarNode(.worktree(wt))

                // Group agents by tmux window using Dictionary
                var windowGroups: [String: [AgentModel]] = [:]
                var agentOrder: [String] = []  // preserve first-seen order
                for agent in wt.agents {
                    let target = agent.tmuxTarget
                    let windowKey: String
                    if let dotIndex = target.lastIndex(of: ".") {
                        windowKey = String(target[target.startIndex..<dotIndex])
                    } else {
                        windowKey = target
                    }
                    if windowGroups[windowKey] == nil {
                        agentOrder.append(windowKey)
                    }
                    windowGroups[windowKey, default: []].append(agent)
                }
                for windowKey in agentOrder {
                    let agents = windowGroups[windowKey]!
                    if agents.count > 1 {
                        wtNode.children.append(SidebarNode(.agentGroup(agents, windowKey)))
                    } else {
                        wtNode.children.append(SidebarNode(.agent(agents[0])))
                    }
                }

                for entry in ctx.dashboardSession.entriesForWorktree(wt.id) {
                    wtNode.children.append(SidebarNode(.terminal(entry)))
                }
                projectNode.children.append(wtNode)
            }

            result.append(projectNode)
        }

        return result
    }

    // MARK: - Incremental Diff

    /// Compare old and new tree, apply minimal NSOutlineView mutations.
    /// Reuses existing SidebarNode objects where IDs match to preserve selection and expansion.
    private func applyTreeDiff(from oldTree: [SidebarNode], to newTree: [SidebarNode]) {
        outlineView.beginUpdates()
        diffChildren(old: oldTree, new: newTree, parent: nil)
        outlineView.endUpdates()
    }

    /// Recursively diff children of a parent node (nil = root).
    /// Mutates `projectNodes` (or parent's `children`) in-place so the data source stays consistent.
    private func diffChildren(old oldChildren: [SidebarNode], new newChildren: [SidebarNode], parent: SidebarNode?) {
        let oldIds = oldChildren.map { $0.item.id }
        let newIds = newChildren.map { $0.item.id }

        // Build lookup of old nodes by id
        var oldMap: [String: SidebarNode] = [:]
        for node in oldChildren {
            oldMap[node.item.id] = node
        }

        // Build lookup of new nodes by id
        var newMap: [String: SidebarNode] = [:]
        for node in newChildren {
            newMap[node.item.id] = node
        }

        // 1. Remove items that no longer exist (iterate in reverse to keep indices stable)
        var removedIndices = IndexSet()
        for (index, oldId) in oldIds.enumerated().reversed() {
            if newMap[oldId] == nil {
                removedIndices.insert(index)
            }
        }
        if !removedIndices.isEmpty {
            // Update backing store first
            if let parent = parent {
                for i in removedIndices.reversed() {
                    parent.children.remove(at: i)
                }
            } else {
                for i in removedIndices.reversed() {
                    projectNodes.remove(at: i)
                }
            }
            outlineView.removeItems(at: removedIndices, inParent: parent, withAnimation: .slideUp)
        }

        // 2. Build the surviving list (old items that are still in new, in their old order)
        let survivingOldIds = oldIds.filter { newMap[$0] != nil }

        // 3. Insert new items and reorder to match newIds
        //    Walk through newIds and insert anything not yet present at the right position.
        var currentList = survivingOldIds
        for (targetIndex, newId) in newIds.enumerated() {
            if let currentIndex = currentList.firstIndex(of: newId) {
                if currentIndex != targetIndex {
                    // Move: remove from old position, insert at new position
                    let movingNode = oldMap[newId]!
                    currentList.remove(at: currentIndex)
                    currentList.insert(newId, at: targetIndex)
                    // Update backing store
                    if let parent = parent {
                        parent.children.remove(at: currentIndex)
                        parent.children.insert(movingNode, at: targetIndex)
                    } else {
                        projectNodes.remove(at: currentIndex)
                        projectNodes.insert(movingNode, at: targetIndex)
                    }
                    outlineView.moveItem(at: currentIndex, inParent: parent, to: targetIndex, inParent: parent)
                }
            } else {
                // Genuinely new item — insert
                let newNode = newChildren[targetIndex]
                currentList.insert(newId, at: targetIndex)
                if let parent = parent {
                    parent.children.insert(newNode, at: targetIndex)
                } else {
                    projectNodes.insert(newNode, at: targetIndex)
                }
                outlineView.insertItems(at: IndexSet(integer: targetIndex), inParent: parent, withAnimation: .slideDown)
                // Auto-expand new expandable items
                if case .project = newNode.item {
                    outlineView.expandItem(newNode)
                } else if case .worktree = newNode.item {
                    outlineView.expandItem(newNode)
                }
            }
        }

        // 4. For surviving items: update content if changed, then recurse into children
        for newNode in newChildren {
            guard let oldNode = oldMap[newNode.item.id] else { continue }

            // Always keep the backing model fresh (non-visual fields like
            // tmuxTarget / sessionId may change without affecting the signature)
            let oldSig = oldNode.item.contentSignature
            oldNode.item = newNode.item

            // Only reload the cell view when visible content changed
            if oldSig != newNode.item.contentSignature {
                outlineView.reloadItem(oldNode, reloadChildren: false)
            }

            // Recurse into children for expandable items
            if !oldNode.children.isEmpty || !newNode.children.isEmpty {
                diffChildren(old: oldNode.children, new: newNode.children, parent: oldNode)
            }
        }
    }

    private func expandAll() {
        for projectNode in projectNodes {
            outlineView.expandItem(projectNode)
            for child in projectNode.children {
                outlineView.expandItem(child)
            }
        }
    }

    deinit {
        safetyTimer?.invalidate()
        debounceWorkItem?.cancel()
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        for watcher in manifestWatchers.values {
            watcher.stop()
        }
        manifestWatchers.removeAll()
    }

    // MARK: - Project Helpers

    /// Walk the tree to find which ProjectContext a sidebar item belongs to.
    func projectContext(for item: SidebarItem) -> ProjectContext? {
        switch item {
        case .project(let ctx):
            return ctx
        case .worktree(let wt):
            for node in projectNodes {
                if case .project(let ctx) = node.item {
                    let worktrees = projectWorktrees[ctx.projectRoot] ?? []
                    if worktrees.contains(where: { $0.id == wt.id }) {
                        return ctx
                    }
                }
            }
            return nil
        case .agent(let ag):
            for node in projectNodes {
                if case .project(let ctx) = node.item {
                    let worktrees = projectWorktrees[ctx.projectRoot] ?? []
                    for w in worktrees {
                        if w.agents.contains(where: { $0.id == ag.id }) {
                            return ctx
                        }
                    }
                }
            }
            return nil
        case .agentGroup(let agents, _):
            guard let firstAgent = agents.first else { return nil }
            return projectContext(for: .agent(firstAgent))
        case .terminal(let entry):
            for node in projectNodes {
                if case .project(let ctx) = node.item {
                    if ctx.dashboardSession.entry(byId: entry.id) != nil {
                        return ctx
                    }
                }
            }
            return nil
        }
    }

    /// Worktrees for a given project context.
    func worktrees(for ctx: ProjectContext) -> [WorktreeModel] {
        projectWorktrees[ctx.projectRoot] ?? []
    }

    /// Programmatically select the Nth project node.
    func selectProject(at index: Int) {
        guard index >= 0, index < projectNodes.count else { return }
        let targetNode = projectNodes[index]
        for row in 0..<outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? SidebarNode, node === targetNode {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                onItemSelected?(node.item)
                return
            }
        }
    }

    /// Select the sidebar row matching the given entry ID and fire `onItemSelected`.
    @discardableResult
    func selectItem(byId id: String) -> Bool {
        for row in 0..<outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? SidebarNode else { continue }
            if node.item.id == id {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                onItemSelected?(node.item)
                return true
            }
        }
        return false
    }

    func selectedWorktreeId() -> String? {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? SidebarNode else { return nil }
        switch node.item {
        case .project: return nil
        case .worktree(let wt): return wt.id
        case .agent(let ag):
            // Find parent worktree across all projects
            for (_, worktrees) in projectWorktrees {
                for wt in worktrees where wt.agents.contains(where: { $0.id == ag.id }) {
                    return wt.id
                }
            }
            return nil
        case .agentGroup(let agents, _):
            guard let firstAgent = agents.first else { return nil }
            for (_, worktrees) in projectWorktrees {
                for wt in worktrees where wt.agents.contains(where: { $0.id == firstAgent.id }) {
                    return wt.id
                }
            }
            return nil
        case .terminal(let entry): return entry.parentWorktreeId
        }
    }

    /// Resolve the ProjectContext for the current sidebar selection.
    func selectedProjectContext() -> ProjectContext? {
        guard let item = currentSelectedItem() else {
            return OpenProjects.shared.projects.first
        }
        return projectContext(for: item)
    }

    // MARK: - Per-Project + Button

    @objc private func projectAddButtonClicked(_ sender: NSButton) {
        let projectIndex = sender.tag
        guard let ctx = OpenProjects.shared.project(at: projectIndex) else { return }

        let menu = NSMenu()

        let worktreeItem = NSMenuItem(title: "New Worktree", action: #selector(menuNewWorktreeForProject(_:)), keyEquivalent: "")
        worktreeItem.target = self
        worktreeItem.representedObject = ctx
        menu.addItem(worktreeItem)

        menu.addItem(.separator())

        let agentItem = NSMenuItem(title: "New Agent", action: #selector(menuNewAgentForProject(_:)), keyEquivalent: "")
        agentItem.target = self
        agentItem.representedObject = ctx
        menu.addItem(agentItem)

        let termItem = NSMenuItem(title: "New Terminal", action: #selector(menuNewTerminalForProject(_:)), keyEquivalent: "")
        termItem.target = self
        termItem.representedObject = ctx
        menu.addItem(termItem)

        let point = NSPoint(x: 0, y: sender.bounds.height)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc private func menuNewWorktreeForProject(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? ProjectContext else { return }
        onAddWorktree?(ctx)
    }

    @objc private func menuNewAgentForProject(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? ProjectContext else { return }
        let worktreeId = selectedWorktreeId()
        onAddAgent?(ctx, worktreeId)
    }

    @objc private func menuNewTerminalForProject(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? ProjectContext else { return }
        let worktreeId = selectedWorktreeId()
        onAddTerminal?(ctx, worktreeId)
    }

    // MARK: - Per-Worktree + Button

    @objc private func worktreeAddButtonClicked(_ sender: NSButton) {
        guard let worktreeId = sender.identifier?.rawValue else { return }

        // Resolve the project context for this worktree
        var ctx: ProjectContext?
        for node in projectNodes {
            if case .project(let projCtx) = node.item {
                let worktrees = projectWorktrees[projCtx.projectRoot] ?? []
                if worktrees.contains(where: { $0.id == worktreeId }) {
                    ctx = projCtx
                    break
                }
            }
        }
        guard let ctx else { return }

        let ref = WorktreeMenuRef(ctx: ctx, worktreeId: worktreeId)

        let menu = NSMenu()

        let agentItem = NSMenuItem(title: "New Agent", action: #selector(menuNewAgentForWorktree(_:)), keyEquivalent: "")
        agentItem.target = self
        agentItem.representedObject = ref
        menu.addItem(agentItem)

        let termItem = NSMenuItem(title: "New Terminal", action: #selector(menuNewTerminalForWorktree(_:)), keyEquivalent: "")
        termItem.target = self
        termItem.representedObject = ref
        menu.addItem(termItem)

        let point = NSPoint(x: 0, y: sender.bounds.height)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc private func menuNewAgentForWorktree(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? WorktreeMenuRef else { return }
        onAddAgent?(ref.ctx, ref.worktreeId)
    }

    @objc private func menuNewTerminalForWorktree(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? WorktreeMenuRef else { return }
        onAddTerminal?(ref.ctx, ref.worktreeId)
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return projectNodes.count
        }
        if let node = item as? SidebarNode {
            return node.children.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return projectNodes[index]
        }
        if let node = item as? SidebarNode {
            return node.children[index]
        }
        fatalError("Unexpected item type")
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? SidebarNode else { return false }
        switch node.item {
        case .project, .worktree: return true
        case .agent, .agentGroup, .terminal: return false
        }
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }
        switch node.item {
        case .project(let ctx):
            return makeProjectCell(ctx)
        case .worktree(let wt):
            return makeWorktreeCell(wt)
        case .agent(let ag):
            return makeAgentCell(ag)
        case .agentGroup(let agents, _):
            return makeAgentGroupCell(agents)
        case .terminal(let entry):
            return makeTerminalEntryCell(entry)
        }
    }

    private func makeProjectCell(_ ctx: ProjectContext) -> NSView {
        let cell = NSTableCellView()
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "Project")!)
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let name = NSTextField(labelWithString: ctx.projectName.isEmpty ? "master" : ctx.projectName)
        name.font = .boldSystemFont(ofSize: 13)

        // Inline "+" button
        let addBtn = NSButton()
        addBtn.bezelStyle = .glass
        addBtn.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")
        addBtn.target = self
        addBtn.action = #selector(projectAddButtonClicked(_:))
        addBtn.tag = OpenProjects.shared.indexOf(root: ctx.projectRoot) ?? 0
        addBtn.setContentHuggingPriority(.required, for: .horizontal)

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(name)
        stack.addArrangedSubview(NSView()) // spacer
        stack.addArrangedSubview(addBtn)

        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makeWorktreeCell(_ worktree: WorktreeModel) -> NSView {
        let cell = NSTableCellView()
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Worktree")!)
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let name = NSTextField(labelWithString: worktree.name)
        name.font = .boldSystemFont(ofSize: 13)

        let detail = NSTextField(labelWithString: "\(worktree.branch) · \(worktree.status)")
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor

        textStack.addArrangedSubview(name)
        textStack.addArrangedSubview(detail)

        // Inline "+" button for adding agents/terminals to this worktree
        let addBtn = NSButton()
        addBtn.bezelStyle = .glass
        addBtn.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")
        addBtn.target = self
        addBtn.action = #selector(worktreeAddButtonClicked(_:))
        addBtn.identifier = NSUserInterfaceItemIdentifier(worktree.id)
        addBtn.setContentHuggingPriority(.required, for: .horizontal)

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(textStack)
        stack.addArrangedSubview(NSView()) // spacer
        stack.addArrangedSubview(addBtn)

        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makeAgentCell(_ agent: AgentModel) -> NSView {
        let cell = NSTableCellView()
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false

        let statusDesc = "Agent \(agent.status.rawValue)"
        let icon = NSImageView(image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: statusDesc)!)
        icon.contentTintColor = statusColor(for: agent.status)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 6, weight: .regular)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 8).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 8).isActive = true

        let displayName = agent.name.isEmpty ? agent.id : agent.name
        let label = NSTextField(labelWithString: "\(displayName) — \(agent.agentType)")
        cell.setAccessibilityLabel("\(displayName), \(agent.agentType), \(agent.status.rawValue)")
        label.font = .systemFont(ofSize: 12)

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)

        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makeAgentGroupCell(_ agents: [AgentModel]) -> NSView {
        let cell = NSTableCellView()
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Use the "worst" status for the group color (failed > running > completed)
        let leadStatus = agents.first?.status ?? .running
        let statusDesc = "\(agents.count) agents (split)"
        let icon = NSImageView(image: NSImage(systemSymbolName: "rectangle.split.2x1.fill", accessibilityDescription: statusDesc)!)
        icon.contentTintColor = statusColor(for: leadStatus)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .regular)
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let label = NSTextField(labelWithString: "\(agents.count) agents (split)")
        label.font = .systemFont(ofSize: 12)

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)

        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makeTerminalEntryCell(_ entry: DashboardSession.TerminalEntry) -> NSView {
        let cell = NSTableCellView()
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let symbolName: String
        let tintColor: NSColor
        switch entry.kind {
        case .agent:
            symbolName = "circle.fill"
            tintColor = .systemGreen
        case .terminal:
            symbolName = "terminal.fill"
            tintColor = .labelColor
        }

        let kindDesc = entry.kind == .agent ? "Agent" : "Terminal"
        let icon = NSImageView(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: kindDesc)!)
        icon.contentTintColor = tintColor
        if entry.kind == .agent {
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 6, weight: .regular)
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 8).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 8).isActive = true
        }
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let label = NSTextField(labelWithString: entry.label)
        label.font = .systemFont(ofSize: 12)

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)

        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    // MARK: - Context Menu

    @objc private func contextRename(_ sender: Any) {
        guard let node = contextClickedNode else { return }

        let currentLabel: String
        switch node.item {
        case .terminal(let entry): currentLabel = entry.label
        case .agent(let agent): currentLabel = agent.name.isEmpty ? agent.id : agent.name
        default: return
        }

        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = "Enter a new name:"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = currentLabel
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newLabel = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !newLabel.isEmpty else { return }

        guard let ctx = projectContext(for: node.item) else { return }

        switch node.item {
        case .terminal(let entry): onRenameTerminal?(ctx, entry.id, newLabel)
        case .agent(let agent): onRenameAgent?(ctx, agent.id, newLabel)
        default: break
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0,
              let node = outlineView.item(atRow: clickedRow) as? SidebarNode else {
            contextClickedNode = nil
            return
        }

        switch node.item {
        case .project:
            contextClickedNode = node
            menu.addItem(withTitle: "Close Project", action: #selector(contextCloseProject(_:)), keyEquivalent: "").target = self
        case .worktree:
            contextClickedNode = node
            menu.addItem(withTitle: "Delete Worktree", action: #selector(contextDeleteWorktree(_:)), keyEquivalent: "").target = self
        case .agent:
            contextClickedNode = node
            menu.addItem(withTitle: "Rename…", action: #selector(contextRename(_:)), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Delete", action: #selector(contextDelete(_:)), keyEquivalent: "").target = self
        case .agentGroup:
            contextClickedNode = nil  // no context menu for groups yet
        case .terminal:
            contextClickedNode = node
            menu.addItem(withTitle: "Rename…", action: #selector(contextRename(_:)), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Delete", action: #selector(contextDelete(_:)), keyEquivalent: "").target = self
        }
    }

    @objc private func contextCloseProject(_ sender: Any) {
        guard let node = contextClickedNode, case .project(let ctx) = node.item else { return }
        OpenProjects.shared.remove(root: ctx.projectRoot)
        refresh()
    }

    @objc private func contextDeleteWorktree(_ sender: Any) {
        guard let node = contextClickedNode, case .worktree(let wt) = node.item else { return }
        guard let ctx = projectContext(for: node.item) else { return }

        let alert = NSAlert()
        alert.messageText = "Delete worktree \"\(wt.name)\"?"
        alert.informativeText = "This will kill all agents, remove the git worktree, and delete the branch."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        onDeleteWorktree?(ctx, wt.id)
    }

    @objc private func contextDelete(_ sender: Any) {
        guard let node = contextClickedNode else { return }
        guard let ctx = projectContext(for: node.item) else { return }

        switch node.item {
        case .terminal(let entry):
            let alert = NSAlert()
            alert.messageText = "Delete \"\(entry.label)\"?"
            alert.informativeText = "This will terminate the process and remove it from the sidebar."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            onDeleteTerminal?(ctx, entry.id)

        case .agent(let agent):
            let displayName = agent.name.isEmpty ? agent.id : agent.name
            let alert = NSAlert()
            alert.messageText = "Delete agent \"\(displayName)\"?"
            alert.informativeText = "This will kill the agent and remove it from the manifest."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            onDeleteAgent?(ctx, agent.id)

        default:
            break
        }
    }

    // MARK: - Selection

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelectionCallback else { return }

        if activeTab != nil {
            deselectAllTabs()
        }

        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? SidebarNode else {
            return
        }
        onItemSelected?(node.item)
    }
}

// MARK: - ManifestWatcher

/// Watches a single file for .write events using GCD's DispatchSource (FSEvents under the hood).
/// Calls `onChange` on the main queue whenever the file is modified.
/// All state mutations must happen on the main thread.
private class ManifestWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let path: String
    private let onChange: () -> Void

    /// Whether the watcher has an active file descriptor and dispatch source.
    var isWatching: Bool { source != nil }

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
        startWatching()
    }

    /// Re-attempt watching if the file didn't exist at creation time.
    func retry() {
        guard source == nil else { return }
        startWatching()
    }

    private func startWatching() {
        // Tear down any existing watcher to prevent fd leak
        if source != nil { stopSource() }

        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                // File was replaced (atomic write) — re-open on main thread
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.startWatching()
                    self?.onChange()
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.onChange()
                }
            }
        }

        source.setCancelHandler { [fd = fileDescriptor] in
            close(fd)
        }

        source.resume()
        self.source = source
    }

    private func stopSource() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    func stop() {
        stopSource()
    }

    deinit {
        stop()
    }
}

// MARK: - SidebarNavRow

/// Full-width clickable row for sidebar navigation (Slack/Notion style).
class SidebarNavRow: NSView {

    private static let selectedBackground = NSColor.white.withAlphaComponent(0.08)
    private static let hoverBackground = NSColor.white.withAlphaComponent(0.05)
    private static let rowHeight: CGFloat = 26

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var onClick: (() -> Void)?
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    var isSelected: Bool = false {
        didSet { needsDisplay = true; updateAppearance() }
    }

    init(title: String, icon: String, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 5

        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
        iconView.contentTintColor = terminalForeground.withAlphaComponent(0.7)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(iconView)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = terminalForeground.withAlphaComponent(0.7)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.rowHeight),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func updateAppearance() {
        if isSelected {
            layer?.backgroundColor = Self.selectedBackground.cgColor
            iconView.contentTintColor = terminalForeground
            titleLabel.textColor = terminalForeground
        } else if isHovered {
            layer?.backgroundColor = Self.hoverBackground.cgColor
            iconView.contentTintColor = terminalForeground.withAlphaComponent(0.7)
            titleLabel.textColor = terminalForeground.withAlphaComponent(0.7)
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            iconView.contentTintColor = terminalForeground.withAlphaComponent(0.7)
            titleLabel.textColor = terminalForeground.withAlphaComponent(0.7)
        }
    }

    // MARK: - Mouse Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
