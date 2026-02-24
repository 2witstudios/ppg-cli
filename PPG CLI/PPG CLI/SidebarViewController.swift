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
}

// Wrapper class for use as NSOutlineView item (requires reference type identity)
class SidebarNode {
    let item: SidebarItem
    var children: [SidebarNode] = []

    init(_ item: SidebarItem) {
        self.item = item
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

    private var refreshTimer: Timer?
    var projectNodes: [SidebarNode] = []
    private var selectedItemId: String?
    private var suppressSelectionCallback = false
    private var userIsSelecting = false
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

        let contextMenu = NSMenu()
        contextMenu.delegate = self
        outlineView.menu = contextMenu

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        outlineView.backgroundColor = .clear
        view.addSubview(scrollView)

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
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
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

    @objc private func settingsButtonClicked() {
        onSettingsClicked?()
    }

    @objc private func addProjectButtonClicked() {
        onAddProject?()
    }

    // MARK: - Refresh

    private func startRefreshTimer() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        let openProjects = OpenProjects.shared.projects

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var results: [String: [WorktreeModel]] = [:]
            let group = DispatchGroup()

            for ctx in openProjects {
                group.enter()
                let worktrees = PPGService.shared.refreshStatus(manifestPath: ctx.manifestPath)
                results[ctx.projectRoot] = worktrees
                group.leave()
            }

            group.wait()

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.selectedItemId = self.currentSelectedId()
                self.projectWorktrees = results
                self.rebuildTree()
                self.suppressSelectionCallback = true
                self.outlineView.reloadData()
                self.expandAll()
                if !self.userIsSelecting {
                    self.restoreSelection()
                }
                self.suppressSelectionCallback = false

                let currentItem = self.currentSelectedItem()
                self.onDataRefreshed?(currentItem)
            }
        }
    }

    private func currentSelectedId() -> String? {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? SidebarNode else { return nil }
        return node.item.id
    }

    private func currentSelectedItem() -> SidebarItem? {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? SidebarNode else { return nil }
        return node.item
    }

    private func rebuildTree() {
        projectNodes = []

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

                // Group agents that share the same tmux window
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

            projectNodes.append(projectNode)
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

    private func restoreSelection() {
        guard let targetId = selectedItemId else { return }
        for row in 0..<outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? SidebarNode, node.item.id == targetId {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                return
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
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

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(textStack)

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
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let statusDesc = "Agent \(agent.status.rawValue)"
        let icon = NSImageView(image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: statusDesc)!)
        icon.contentTintColor = statusColor(for: agent.status)
        icon.setContentHuggingPriority(.required, for: .horizontal)

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
        userIsSelecting = true
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? SidebarNode else {
            userIsSelecting = false
            return
        }
        onItemSelected?(node.item)
        DispatchQueue.main.async { [weak self] in
            self?.userIsSelecting = false
        }
    }
}
