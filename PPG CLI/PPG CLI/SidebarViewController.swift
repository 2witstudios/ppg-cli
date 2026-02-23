import AppKit

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
    case master
    case worktree(WorktreeModel)
    case agent(AgentModel)
    case terminal(DashboardSession.TerminalEntry)

    var id: String {
        switch self {
        case .master: return "__master__"
        case .worktree(let wt): return wt.id
        case .agent(let ag): return ag.id
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
    let addButton = NSButton()

    var worktrees: [WorktreeModel] = []
    var dashboardSession: DashboardSession = .shared

    var onItemSelected: ((SidebarItem) -> Void)?
    var onAddAgent: ((String?) -> Void)?
    var onAddTerminal: ((String?) -> Void)?
    var onAddWorktree: (() -> Void)?
    var onRenameTerminal: ((String, String) -> Void)?   // (id, newLabel)
    var onDeleteTerminal: ((String) -> Void)?            // (id)
    var onRenameAgent: ((String, String) -> Void)?       // (agentId, newName)
    var onKillAgent: ((String) -> Void)?                 // (agentId)
    var onDataRefreshed: ((SidebarItem?) -> Void)?       // current selection after refresh

    private var refreshTimer: Timer?
    private var masterNode: SidebarNode?
    private var selectedItemId: String?
    private var suppressSelectionCallback = false
    private var userIsSelecting = false
    private var contextClickedNode: SidebarNode?

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Header with + button
        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.spacing = 4
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let headerLabel = NSTextField(labelWithString: "Project")
        headerLabel.font = .systemFont(ofSize: 12, weight: .medium)
        headerLabel.textColor = .tertiaryLabelColor

        addButton.bezelStyle = .glass
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")
        addButton.target = self
        addButton.action = #selector(addButtonClicked(_:))
        addButton.setContentHuggingPriority(.required, for: .horizontal)

        headerStack.addArrangedSubview(headerLabel)
        headerStack.addArrangedSubview(NSView()) // spacer
        headerStack.addArrangedSubview(addButton)
        view.addSubview(headerStack)

        // Outline view
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
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            headerStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            headerStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            headerStack.heightAnchor.constraint(equalToConstant: 24),

            scrollView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        startRefreshTimer()
    }

    // MARK: - Refresh

    private func startRefreshTimer() {
        // Initial refresh
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        // Capture shared state on main thread before dispatching to background
        let manifestPath = ProjectState.shared.manifestPath
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let newWorktrees = PPGService.shared.refreshStatus(manifestPath: manifestPath)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.selectedItemId = self.currentSelectedId()
                self.worktrees = newWorktrees
                self.rebuildTree()
                self.suppressSelectionCallback = true   // suppress BEFORE reloadData
                self.outlineView.reloadData()
                self.expandAll()
                if !self.userIsSelecting {
                    self.restoreSelection()
                }
                self.suppressSelectionCallback = false

                // Notify with current selection
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
        let master = SidebarNode(.master)

        // Master-level dashboard entries (agents + terminals)
        for entry in dashboardSession.entriesForMaster() {
            master.children.append(SidebarNode(.terminal(entry)))
        }

        // Worktrees from manifest
        for wt in worktrees {
            let wtNode = SidebarNode(.worktree(wt))
            // Manifest agents
            for agent in wt.agents {
                wtNode.children.append(SidebarNode(.agent(agent)))
            }
            // Dashboard entries for this worktree
            for entry in dashboardSession.entriesForWorktree(wt.id) {
                wtNode.children.append(SidebarNode(.terminal(entry)))
            }
            master.children.append(wtNode)
        }

        masterNode = master
    }

    private func expandAll() {
        guard let master = masterNode else { return }
        outlineView.expandItem(master)
        for child in master.children {
            outlineView.expandItem(child)
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

    // MARK: - + Button

    @objc private func addButtonClicked(_ sender: NSButton) {
        let menu = NSMenu()

        menu.addItem(withTitle: "New Worktree", action: #selector(menuNewWorktree), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "New Agent", action: #selector(menuNewAgent), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "New Terminal", action: #selector(menuNewTerminal), keyEquivalent: "")
            .target = self

        let point = NSPoint(x: 0, y: sender.bounds.height)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc private func menuNewWorktree() {
        onAddWorktree?()
    }

    @objc private func menuNewAgent() {
        let worktreeId = selectedWorktreeId()
        onAddAgent?(worktreeId)
    }

    @objc private func menuNewTerminal() {
        let worktreeId = selectedWorktreeId()
        onAddTerminal?(worktreeId)
    }

    func selectedWorktreeId() -> String? {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? SidebarNode else { return nil }
        switch node.item {
        case .master: return nil
        case .worktree(let wt): return wt.id
        case .agent(let ag):
            // Find parent worktree
            for wt in worktrees where wt.agents.contains(where: { $0.id == ag.id }) {
                return wt.id
            }
            return nil
        case .terminal(let entry): return entry.parentWorktreeId
        }
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return masterNode != nil ? 1 : 0
        }
        if let node = item as? SidebarNode {
            return node.children.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return masterNode!
        }
        if let node = item as? SidebarNode {
            return node.children[index]
        }
        fatalError("Unexpected item type")
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? SidebarNode else { return false }
        switch node.item {
        case .master, .worktree: return true
        case .agent, .terminal: return false
        }
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }
        switch node.item {
        case .master:
            return makeMasterCell()
        case .worktree(let wt):
            return makeWorktreeCell(wt)
        case .agent(let ag):
            return makeAgentCell(ag)
        case .terminal(let entry):
            return makeTerminalEntryCell(entry)
        }
    }

    private func makeMasterCell() -> NSView {
        let cell = NSTableCellView()
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "Project")!)
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let name = NSTextField(labelWithString: ProjectState.shared.projectName.isEmpty ? "master" : ProjectState.shared.projectName)
        name.font = .boldSystemFont(ofSize: 13)

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(name)

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

        switch node.item {
        case .terminal(let entry): onRenameTerminal?(entry.id, newLabel)
        case .agent(let agent): onRenameAgent?(agent.id, newLabel)
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
        case .agent:
            contextClickedNode = node
            menu.addItem(withTitle: "Rename…", action: #selector(contextRename(_:)), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Kill", action: #selector(contextDelete(_:)), keyEquivalent: "").target = self
        case .terminal:
            contextClickedNode = node
            menu.addItem(withTitle: "Rename…", action: #selector(contextRename(_:)), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Delete", action: #selector(contextDelete(_:)), keyEquivalent: "").target = self
        default:
            contextClickedNode = nil
        }
    }

    @objc private func contextDelete(_ sender: Any) {
        guard let node = contextClickedNode else { return }

        switch node.item {
        case .terminal(let entry):
            let alert = NSAlert()
            alert.messageText = "Delete \"\(entry.label)\"?"
            alert.informativeText = "This will terminate the process and remove it from the sidebar."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            onDeleteTerminal?(entry.id)

        case .agent(let agent):
            let displayName = agent.name.isEmpty ? agent.id : agent.name
            let alert = NSAlert()
            alert.messageText = "Kill agent \"\(displayName)\"?"
            alert.informativeText = "This will send Ctrl-C and terminate the agent's tmux pane."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Kill")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            onKillAgent?(agent.id)

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
        // Reset after a short delay so the next timer-driven refresh can restore selection
        DispatchQueue.main.async { [weak self] in
            self?.userIsSelecting = false
        }
    }
}
