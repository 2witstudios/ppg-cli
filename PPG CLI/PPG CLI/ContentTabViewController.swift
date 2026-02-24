import AppKit
import SwiftTerm

enum TabEntry {
    case manifestAgent(AgentModel, sessionName: String)
    case agentGroup([AgentModel], String, sessionName: String)  // agents sharing a tmux window, tmuxTarget, sessionName
    case sessionEntry(DashboardSession.TerminalEntry, sessionName: String)

    var id: String {
        switch self {
        case .manifestAgent(let agent, _): return agent.id
        case .agentGroup(let agents, _, _): return agents.map(\.id).joined(separator: "+")
        case .sessionEntry(let entry, _): return entry.id
        }
    }

    var label: String {
        switch self {
        case .manifestAgent(let agent, _): return agent.name.isEmpty ? agent.id : agent.name
        case .agentGroup(let agents, _, _): return "\(agents.count) agents (split)"
        case .sessionEntry(let entry, _): return entry.label
        }
    }

    var sessionName: String {
        switch self {
        case .manifestAgent(_, let name): return name
        case .agentGroup(_, _, let name): return name
        case .sessionEntry(_, let name): return name
        }
    }
}

class ContentViewController: NSViewController {
    let placeholderLabel = NSTextField(labelWithString: "Select an item from the sidebar")
    private let containerView = NSView()
    private(set) var currentEntry: TabEntry?
    private var terminalViews: [String: NSView] = [:]
    private var worktreeDetailView: WorktreeDetailView?
    private var homeDashboardView: HomeDashboardView?
    private var promptsView: PromptsView?
    private var swarmsView: SwarmsView?
    private var dashboardConstraints: [NSLayoutConstraint] = []
    private var promptsConstraints: [NSLayoutConstraint] = []
    private var swarmsConstraints: [NSLayoutConstraint] = []

    // MARK: - Terminal Tracking (LRU eviction + status dedup)
    private struct TerminalTrackingState {
        var lastAccess: Date
        var evictionStatus: AgentStatus
        /// Fingerprint of last-seen mutable fields, used to skip redundant status label updates.
        var lastChangeKey: String
    }
    private var terminalTracking: [String: TerminalTrackingState] = [:]
    /// Timer for periodic eviction of idle completed-agent terminals.
    private var evictionTimer: Timer?
    /// How long a non-visible completed terminal lives before eviction.
    private static let evictionDelay: TimeInterval = 30

    // MARK: - Grid Mode
    private(set) var paneGrid: PaneGridController?  // currently visible grid
    private var gridsByEntry: [String: PaneGridController] = [:]  // all grids (active + suspended)
    private(set) var activeGridOwnerId: String?  // which entry owns the visible grid
    /// Called when a grid is permanently destroyed (exitGridMode or removeGrid). Parameter: owner entry ID.
    var onGridDestroyed: ((String) -> Void)?
    /// Called when a grid is suspended (navigate away). Parameters: owner entry ID, layout snapshot.
    var onGridSuspended: ((String, GridLayoutNode) -> Void)?
    var isGridMode: Bool {
        guard let grid = paneGrid else { return false }
        return grid.view.superview != nil && !grid.view.isHidden
    }

    var currentEntryId: String? {
        if isGridMode { return paneGrid?.focusedEntry?.id }
        return currentEntry?.id
    }
    var isShowingWorktreeDetail: Bool { worktreeDetailView?.superview != nil }
    var isShowingHomeDashboard: Bool { homeDashboardView?.superview != nil }
    var isShowingPromptsView: Bool { promptsView?.superview != nil }
    var isShowingSwarmsView: Bool { swarmsView?.superview != nil }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.wantsLayer = true
        view.layer?.backgroundColor = chromeBackground.cgColor

        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = terminalBackground.cgColor
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        placeholderLabel.font = .systemFont(ofSize: 16)
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.alignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            placeholderLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        // Start the periodic eviction timer for idle completed-agent terminals
        evictionTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.evictStaleTerminals()
        }
    }

    deinit {
        evictionTimer?.invalidate()
    }

    /// Evict terminal views for completed/killed/failed agents that haven't been
    /// viewed in `evictionDelay` seconds and are not currently visible.
    private func evictStaleTerminals() {
        let now = Date()
        let visibleId = currentEntry?.id
        let gridVisibleIds: Set<String> = {
            guard let grid = paneGrid, isGridMode else { return [] }
            return Set(grid.root.allLeafIds().compactMap { grid.root.entry(forLeafId: $0)?.id })
        }()

        for (id, state) in terminalTracking {
            let status = state.evictionStatus
            guard status == .completed || status == .killed || status == .failed else { continue }
            guard id != visibleId, !gridVisibleIds.contains(id) else { continue }
            guard now.timeIntervalSince(state.lastAccess) > Self.evictionDelay else { continue }

            // Evict: explicitly tear down and remove cached view
            if let termView = terminalViews[id] {
                tearDownTerminal(termView)
                termView.removeFromSuperview()
                terminalViews.removeValue(forKey: id)
            }
            terminalTracking.removeValue(forKey: id)
        }
    }

    func showEntry(_ entry: TabEntry?) {
        homeDashboardView?.removeFromSuperview()
        worktreeDetailView?.removeFromSuperview()
        promptsView?.removeFromSuperview()
        swarmsView?.removeFromSuperview()

        // Suspend any active grid — sidebar clicks always navigate, never fill panes
        suspendGrid()

        guard let entry = entry else {
            // Show placeholder
            for (_, termView) in terminalViews where termView.superview === containerView {
                termView.isHidden = true
            }
            currentEntry = nil
            placeholderLabel.isHidden = false
            containerView.isHidden = true
            return
        }

        // Same entry already showing — no-op
        if let current = currentEntry, current.id == entry.id {
            return
        }

        currentEntry = entry
        placeholderLabel.isHidden = true
        containerView.isHidden = false

        for (_, termView) in terminalViews where termView.superview === containerView {
            termView.isHidden = true
        }

        let termView = terminalView(for: entry)
        termView.isHidden = false

        // Track access time for LRU eviction
        terminalTracking[entry.id, default: TerminalTrackingState(
            lastAccess: Date(), evictionStatus: .running, lastChangeKey: ""
        )].lastAccess = Date()
    }

    func updateCurrentEntry(_ entry: TabEntry) {
        // Extract the agent status (if any) for eviction tracking
        let agentStatus: AgentStatus? = {
            switch entry {
            case .manifestAgent(let agent, _): return agent.status
            case .agentGroup(let agents, _, _): return agents.first?.status ?? .lost
            case .sessionEntry: return nil
            }
        }()

        // Build a change fingerprint from mutable fields (status + label)
        let changeKey = "\(agentStatus?.rawValue ?? "")-\(entry.label)"

        // Always update eviction tracking regardless of dedup
        if let status = agentStatus {
            terminalTracking[entry.id, default: TerminalTrackingState(
                lastAccess: Date(), evictionStatus: status, lastChangeKey: ""
            )].evictionStatus = status
        }

        // Update in grid mode — always forward, no dedup (grid manages its own state)
        if isGridMode, let grid = paneGrid, grid.containsEntry(id: entry.id) {
            grid.updateEntry(entry)
            // Update tracking fingerprint after forwarding
            terminalTracking[entry.id]?.lastChangeKey = changeKey
            return
        }

        guard let current = currentEntry, current.id == entry.id else { return }

        // Skip expensive status label update if nothing changed
        let isChanged = terminalTracking[entry.id]?.lastChangeKey != changeKey
        terminalTracking[entry.id]?.lastChangeKey = changeKey

        currentEntry = entry
        guard isChanged else { return }

        switch entry {
        case .manifestAgent(let agent, _):
            if let pane = terminalViews[agent.id] as? TerminalPane {
                pane.updateStatus(agent.status)
            }
        case .agentGroup(let agents, _, _):
            if let pane = terminalViews[entry.id] as? TerminalPane {
                let status = agents.first?.status ?? .lost
                pane.updateStatus(status)
            }
        case .sessionEntry:
            break
        }
    }

    func removeEntry(byId id: String) {
        if let termView = terminalViews[id] {
            terminateTerminal(termView)
            termView.removeFromSuperview()
            terminalViews.removeValue(forKey: id)
        }
        terminalTracking.removeValue(forKey: id)
        removeGrid(forEntryId: id)
        if currentEntry?.id == id {
            currentEntry = nil
            worktreeDetailView?.removeFromSuperview()
            placeholderLabel.isHidden = false
            containerView.isHidden = true
        }
    }

    func clearStaleViews(validIds: Set<String>) {
        let staleIds = terminalViews.keys.filter { !validIds.contains($0) }
        for id in staleIds {
            if let termView = terminalViews[id] {
                terminateTerminal(termView)
                termView.removeFromSuperview()
                terminalViews.removeValue(forKey: id)
            }
            terminalTracking.removeValue(forKey: id)
        }
        // Clean up grids whose owner entry no longer exists
        let staleGridIds = gridsByEntry.keys.filter { !validIds.contains($0) }
        for id in staleGridIds {
            removeGrid(forEntryId: id)
        }
    }

    // MARK: - Grid Mode

    /// Lazily create the grid controller for the given entry.
    func ensureGridController(forEntryId entryId: String) -> PaneGridController {
        if let existing = gridsByEntry[entryId] {
            return existing
        }
        let grid = PaneGridController()
        grid.terminalViewProvider = { [weak self] entry in
            guard let self = self else { return NSView() }
            return self.terminalView(for: entry, forGrid: true)
        }
        grid.terminalTerminator = { [weak self] view in
            guard let self = self else { return }
            self.terminateTerminal(view)
            // Remove cached terminal view so re-selecting this entry creates a fresh one
            if let id = self.terminalViews.first(where: { $0.value === view })?.key {
                self.terminalViews.removeValue(forKey: id)
            }
        }
        gridsByEntry[entryId] = grid
        return grid
    }

    /// Convenience: resolve entry ID from activeGridOwnerId or currentEntry.
    func ensureGridController() -> PaneGridController {
        let entryId = activeGridOwnerId ?? currentEntry?.id ?? "__unknown__"
        return ensureGridController(forEntryId: entryId)
    }

    private func enterGridMode(forEntryId entryId: String) {
        let grid = ensureGridController(forEntryId: entryId)

        // Hide single-pane content
        for (_, termView) in terminalViews {
            termView.isHidden = true
        }
        placeholderLabel.isHidden = true
        containerView.isHidden = true

        // Add grid view to main view
        addChild(grid)
        grid.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid.view)
        NSLayoutConstraint.activate([
            grid.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            grid.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            grid.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            grid.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Transfer the current entry into the first leaf, reusing the existing terminal view
        if let entry = currentEntry {
            let existingView = terminalViews.removeValue(forKey: entry.id)
            grid.setInitialEntry(entry, existingView: existingView)
        }

        paneGrid = grid
        activeGridOwnerId = entryId
        currentEntry = nil
    }

    func splitPaneBelow() {
        guard let entryId = currentEntry?.id ?? activeGridOwnerId else { return }
        if !isGridMode {
            enterGridMode(forEntryId: entryId)
        }
        paneGrid?.splitFocusedPane(direction: .horizontal)
    }

    func splitPaneRight() {
        guard let entryId = currentEntry?.id ?? activeGridOwnerId else { return }
        if !isGridMode {
            enterGridMode(forEntryId: entryId)
        }
        paneGrid?.splitFocusedPane(direction: .vertical)
    }

    func closeFocusedPane() -> Bool {
        guard let grid = paneGrid, isGridMode else { return false }

        if grid.root.leafCount <= 1 {
            // Last pane — exit grid mode entirely
            exitGridMode()
            return true
        }

        return grid.closeFocusedPane()
    }

    func movePaneFocus(direction: SplitDirection, forward: Bool) {
        paneGrid?.moveFocus(direction, forward: forward)
    }

    func exitGridMode() {
        guard let grid = paneGrid else { return }
        let ownerId = activeGridOwnerId

        // Restore the focused entry back into single-pane mode
        if let entry = grid.focusedEntry {
            // Extract the terminal view from the focused cell so we can reuse it
            let focusedCell = grid.cellViews[grid.focusedLeafId]
            let existingView = focusedCell?.detachTerminalView()

            grid.view.removeFromSuperview()
            grid.removeFromParent()

            // Re-install into single-pane container
            currentEntry = entry
            placeholderLabel.isHidden = true
            containerView.isHidden = false

            for (_, termView) in terminalViews where termView.superview === containerView {
                termView.isHidden = true
            }

            if let existingView = existingView {
                existingView.translatesAutoresizingMaskIntoConstraints = false
                containerView.addSubview(existingView)
                let leadingPadding: CGFloat = (existingView is TerminalPane) ? 0 : 8
                NSLayoutConstraint.activate([
                    existingView.topAnchor.constraint(equalTo: containerView.topAnchor),
                    existingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: leadingPadding),
                    existingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                    existingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                ])
                terminalViews[entry.id] = existingView
            } else {
                let termView = terminalView(for: entry)
                termView.isHidden = false
            }
        } else {
            grid.view.removeFromSuperview()
            grid.removeFromParent()
            placeholderLabel.isHidden = false
            containerView.isHidden = true
        }

        // Tear down remaining grid terminals (non-focused panes)
        grid.terminateAllExcept(leafId: grid.focusedLeafId, using: { [weak self] view in
            self?.terminateTerminal(view)
        })

        // Remove grid from storage — exit is permanent (unlike suspend)
        if let ownerId = ownerId {
            gridsByEntry.removeValue(forKey: ownerId)
            onGridDestroyed?(ownerId)
        }
        paneGrid = nil
        activeGridOwnerId = nil
    }

    /// Detach the active grid from the view hierarchy without destroying it.
    /// Terminal views remain alive inside the grid's cellViews.
    func suspendGrid() {
        guard let grid = paneGrid, let ownerId = activeGridOwnerId else { return }
        // Save layout before detaching
        onGridSuspended?(ownerId, grid.root.toLayoutNode())
        grid.view.removeFromSuperview()
        grid.removeFromParent()
        paneGrid = nil
        activeGridOwnerId = nil
    }

    /// Restore a previously suspended grid for the given entry.
    /// Returns true if a grid was found and restored.
    func restoreGrid(forEntryId entryId: String) -> Bool {
        guard let grid = gridsByEntry[entryId] else { return false }

        // Suspend any currently active grid first
        suspendGrid()

        // Hide single-pane content
        homeDashboardView?.removeFromSuperview()
        worktreeDetailView?.removeFromSuperview()
        promptsView?.removeFromSuperview()
        swarmsView?.removeFromSuperview()
        for (_, termView) in terminalViews where termView.superview === containerView {
            termView.isHidden = true
        }
        placeholderLabel.isHidden = true
        containerView.isHidden = true

        // Re-add grid to view hierarchy
        addChild(grid)
        grid.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid.view)
        NSLayoutConstraint.activate([
            grid.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            grid.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            grid.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            grid.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        paneGrid = grid
        activeGridOwnerId = entryId
        currentEntry = nil
        return true
    }

    /// Fully tear down a grid: terminate all terminals, remove from gridsByEntry.
    func removeGrid(forEntryId entryId: String) {
        guard let grid = gridsByEntry.removeValue(forKey: entryId) else {
            // No in-memory grid, but still notify so persisted entries get cleaned up
            onGridDestroyed?(entryId)
            return
        }

        // If this is the active grid, detach it
        if activeGridOwnerId == entryId {
            grid.view.removeFromSuperview()
            grid.removeFromParent()
            paneGrid = nil
            activeGridOwnerId = nil
        }

        // Terminate all terminals in the grid
        grid.terminateAllExcept(leafId: "", using: { [weak self] view in
            self?.terminateTerminal(view)
        })
        onGridDestroyed?(entryId)
    }

    // MARK: - Worktree Detail

    // MARK: - Home Dashboard

    func showHomeDashboard(projects: [ProjectContext], worktreesByProject: [String: [WorktreeModel]]) {
        // Hide terminals, grid, and worktree detail
        suspendGrid()
        for (_, termView) in terminalViews where termView.superview === containerView {
            termView.isHidden = true
        }
        currentEntry = nil
        worktreeDetailView?.removeFromSuperview()
        promptsView?.removeFromSuperview()
        swarmsView?.removeFromSuperview()
        placeholderLabel.isHidden = true
        containerView.isHidden = true

        if homeDashboardView == nil {
            homeDashboardView = HomeDashboardView()
        }
        guard let dashboard = homeDashboardView else { return }

        if dashboard.superview != view {
            dashboard.removeFromSuperview()
            dashboard.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(dashboard)
            if dashboardConstraints.isEmpty {
                dashboardConstraints = [
                    dashboard.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                    dashboard.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                    dashboard.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                    dashboard.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                ]
            }
            NSLayoutConstraint.activate(dashboardConstraints)
        }

        dashboard.configure(projects: projects, worktreesByProject: worktreesByProject)
    }

    func refreshHomeDashboard(projects: [ProjectContext], worktreesByProject: [String: [WorktreeModel]]) {
        guard let dashboard = homeDashboardView, dashboard.superview != nil else { return }
        dashboard.configure(projects: projects, worktreesByProject: worktreesByProject)
    }

    func showWorktreeDetail(
        worktree: WorktreeModel,
        projectRoot: String,
        onNewAgent: @escaping () -> Void,
        onNewTerminal: @escaping () -> Void,
        onNewWorktree: @escaping () -> Void
    ) {
        homeDashboardView?.removeFromSuperview()
        promptsView?.removeFromSuperview()
        swarmsView?.removeFromSuperview()
        suspendGrid()
        // Hide terminal views and clear current entry (only containerView-owned, not grid-owned)
        for (_, termView) in terminalViews where termView.superview === containerView {
            termView.isHidden = true
        }
        currentEntry = nil
        placeholderLabel.isHidden = true
        containerView.isHidden = true

        // Create or reconfigure the detail view
        if worktreeDetailView == nil {
            worktreeDetailView = WorktreeDetailView()
        }
        guard let detailView = worktreeDetailView else { return }

        detailView.configure(
            worktree: worktree,
            onNewAgent: onNewAgent,
            onNewTerminal: onNewTerminal,
            onNewWorktree: onNewWorktree
        )

        if detailView.superview != view {
            detailView.removeFromSuperview()
            detailView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(detailView)
            NSLayoutConstraint.activate([
                detailView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                detailView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                detailView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                detailView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }

        // Load diff on background queue
        let worktreePath = worktree.path
        DispatchQueue.global(qos: .utility).async {
            let diffData = WorktreeDetailView.fetchDiffData(worktreePath: worktreePath)
            DispatchQueue.main.async { [weak detailView] in
                detailView?.updateDiff(diffData)
            }
        }
    }

    func refreshWorktreeDetail() {
        guard let detailView = worktreeDetailView, detailView.superview != nil else { return }
        let worktreePath = detailView.currentWorktreePath
        guard !worktreePath.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            let diffData = WorktreeDetailView.fetchDiffData(worktreePath: worktreePath)
            DispatchQueue.main.async { [weak detailView] in
                detailView?.updateDiff(diffData)
            }
        }
    }

    // MARK: - Prompts & Swarms Views

    func showPromptsView(projects: [ProjectContext]) {
        suspendGrid()
        for (_, termView) in terminalViews where termView.superview === containerView {
            termView.isHidden = true
        }
        currentEntry = nil
        homeDashboardView?.removeFromSuperview()
        worktreeDetailView?.removeFromSuperview()
        swarmsView?.removeFromSuperview()
        placeholderLabel.isHidden = true
        containerView.isHidden = true

        if promptsView == nil {
            promptsView = PromptsView()
        }
        guard let pv = promptsView else { return }

        if pv.superview != view {
            pv.removeFromSuperview()
            pv.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(pv)
            if promptsConstraints.isEmpty {
                promptsConstraints = [
                    pv.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                    pv.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                    pv.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                    pv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                ]
            }
            NSLayoutConstraint.activate(promptsConstraints)
        }

        pv.configure(projects: projects)
    }

    func showSwarmsView(projects: [ProjectContext]) {
        suspendGrid()
        for (_, termView) in terminalViews where termView.superview === containerView {
            termView.isHidden = true
        }
        currentEntry = nil
        homeDashboardView?.removeFromSuperview()
        worktreeDetailView?.removeFromSuperview()
        promptsView?.removeFromSuperview()
        placeholderLabel.isHidden = true
        containerView.isHidden = true

        if swarmsView == nil {
            swarmsView = SwarmsView()
        }
        guard let sv = swarmsView else { return }

        if sv.superview != view {
            sv.removeFromSuperview()
            sv.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(sv)
            if swarmsConstraints.isEmpty {
                swarmsConstraints = [
                    sv.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                    sv.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                    sv.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                    sv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                ]
            }
            NSLayoutConstraint.activate(swarmsConstraints)
        }

        sv.configure(projects: projects)
    }

    // MARK: - Private

    /// Create (or retrieve) a terminal view for a tab entry.
    /// - Parameter forGrid: When true, skip the shared cache and don't parent to containerView.
    ///   The grid cell will own the view directly.
    private func terminalView(for tab: TabEntry, forGrid: Bool = false) -> NSView {
        // Only use the shared cache for single-pane mode
        if !forGrid, let existing = terminalViews[tab.id] {
            return existing
        }

        let sessionName = tab.sessionName
        let termView: NSView
        switch tab {
        case .manifestAgent(let agent, _):
            let pane = TerminalPane(agent: agent, sessionName: sessionName)
            termView = pane

        case .agentGroup(let agents, let tmuxTarget, _):
            let lead = agents[0]
            let groupAgent = AgentModel(
                id: tab.id,
                name: lead.name,
                agentType: lead.agentType,
                status: lead.status,
                tmuxTarget: tmuxTarget,
                prompt: lead.prompt,
                startedAt: lead.startedAt
            )
            let pane = TerminalPane(agent: groupAgent, sessionName: sessionName)
            termView = pane

        case .sessionEntry(let entry, _):
            if let tmuxTarget = entry.tmuxTarget {
                let agentModel = AgentModel(
                    id: entry.id,
                    name: entry.label,
                    agentType: entry.kind == .agent ? "claude" : "terminal",
                    status: .running,
                    tmuxTarget: tmuxTarget,
                    prompt: "",
                    startedAt: "",
                    sessionId: entry.sessionId
                )
                let pane = TerminalPane(agent: agentModel, sessionName: sessionName)
                termView = pane
            } else {
                let localTerm = ScrollableTerminalView(frame: containerView.bounds)
                let cmd = """
                if [ -x /usr/libexec/path_helper ]; then eval $(/usr/libexec/path_helper -s); fi; \
                [ -f ~/.zprofile ] && source ~/.zprofile; \
                [ -f ~/.zshrc ] && source ~/.zshrc; \
                cd \(shellEscape(entry.workingDirectory)) && exec \(entry.command)
                """
                localTerm.startProcess(
                    executable: "/bin/zsh",
                    args: ["-c", cmd],
                    environment: nil,
                    execName: "zsh"
                )
                termView = localTerm
            }
        }

        // Grid-owned views are not parented to containerView or cached
        if forGrid {
            return termView
        }

        termView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(termView)
        // TerminalPane handles its own leading inset; other views get 8px gap from the container.
        let leadingPadding: CGFloat = (termView is TerminalPane) ? 0 : 8
        NSLayoutConstraint.activate([
            termView.topAnchor.constraint(equalTo: containerView.topAnchor),
            termView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: leadingPadding),
            termView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            termView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        terminalViews[tab.id] = termView
        return termView
    }

    private func terminateTerminal(_ view: NSView) {
        if let pane = view as? TerminalPane {
            pane.terminate()
        } else if let scrollTerm = view as? ScrollableTerminalView {
            scrollTerm.process?.terminate()
        } else if let localTerm = view as? LocalProcessTerminalView {
            localTerm.process?.terminate()
        }
    }

    /// Explicit teardown — cancels timers, removes monitors, terminates process.
    /// Used by LRU eviction to ensure PTY/fd cleanup without relying on deinit.
    private func tearDownTerminal(_ view: NSView) {
        if let pane = view as? TerminalPane {
            pane.tearDown()
        } else if let scrollTerm = view as? ScrollableTerminalView {
            scrollTerm.tearDown()
        } else if let localTerm = view as? LocalProcessTerminalView {
            localTerm.process?.terminate()
        }
    }
}

// MARK: - WorktreeDetailView

class WorktreeDetailView: NSView {

    struct DiffData {
        let files: [FileDiff]

        struct FileDiff {
            let filename: String
            let statusCode: String   // M, A, D, ??
            let added: Int
            let removed: Int
            let hunks: [Hunk]
        }

        struct Hunk {
            let header: String       // e.g. "@@ -10,6 +10,8 @@ func login()"
            let lines: [DiffLine]
        }

        struct DiffLine {
            let type: LineType
            let content: String      // code without +/- prefix
            let oldLineNo: Int?
            let newLineNo: Int?
        }

        enum LineType {
            case context, addition, deletion
        }
    }

    // MARK: - Colors

    static let cardBackground = NSColor(srgbRed: 0.14, green: 0.14, blue: 0.15, alpha: 1.0)
    static let cardHeaderBackground = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1.0)
    static let additionBackground = NSColor(srgbRed: 0.13, green: 0.22, blue: 0.15, alpha: 1.0)
    static let deletionBackground = NSColor(srgbRed: 0.25, green: 0.13, blue: 0.13, alpha: 1.0)
    static let additionText = NSColor(srgbRed: 0.55, green: 0.85, blue: 0.55, alpha: 1.0)
    static let deletionText = NSColor(srgbRed: 0.90, green: 0.55, blue: 0.55, alpha: 1.0)
    static let hunkSeparatorColor = NSColor(white: 0.22, alpha: 1.0)

    private(set) var currentWorktreePath = ""

    // Header
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let branchLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let agentButton = NSButton()
    private let terminalButton = NSButton()
    private let worktreeButton = NSButton()
    private let headerStack = NSStackView()

    // Diff area
    private let scrollView = NSScrollView()
    private let diffStackView = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "No unstaged changes")

    var onNewAgent: (() -> Void)?
    var onNewTerminal: (() -> Void)?
    var onNewWorktree: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    func configure(
        worktree: WorktreeModel,
        onNewAgent: @escaping () -> Void,
        onNewTerminal: @escaping () -> Void,
        onNewWorktree: @escaping () -> Void
    ) {
        currentWorktreePath = worktree.path
        nameLabel.stringValue = worktree.name
        branchLabel.stringValue = worktree.branch
        shortcutLabel.stringValue = "Press \(KeybindingManager.shared.displayString(for: .newItem)) or:"
        self.onNewAgent = onNewAgent
        self.onNewTerminal = onNewTerminal
        self.onNewWorktree = onNewWorktree
    }

    func updateDiff(_ data: DiffData) {
        // Remove existing cards
        for view in diffStackView.arrangedSubviews {
            diffStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if data.files.isEmpty {
            emptyLabel.isHidden = false
            diffStackView.isHidden = true
            return
        }

        emptyLabel.isHidden = true
        diffStackView.isHidden = false

        for file in data.files {
            let card = DiffCardView(fileDiff: file)
            diffStackView.addArrangedSubview(card)
            card.translatesAutoresizingMaskIntoConstraints = false
            card.leadingAnchor.constraint(equalTo: diffStackView.leadingAnchor).isActive = true
            card.trailingAnchor.constraint(equalTo: diffStackView.trailingAnchor).isActive = true
        }
    }

    // MARK: - Static Helpers

    static func fetchDiffData(worktreePath: String) -> DiffData {
        let service = PPGService.shared

        // git status --porcelain
        let statusResult = service.runGitCommand(["status", "--porcelain"], cwd: worktreePath)
        // git diff --numstat
        let numstatResult = service.runGitCommand(["diff", "--numstat"], cwd: worktreePath)
        // git diff
        let diffResult = service.runGitCommand(["diff"], cwd: worktreePath)

        // Parse numstat into a lookup: filename -> (added, removed)
        var numstatMap: [String: (Int, Int)] = [:]
        for line in numstatResult.stdout.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.split(separator: "\t", maxSplits: 2)
            if parts.count >= 3 {
                numstatMap[String(parts[2])] = (Int(parts[0]) ?? 0, Int(parts[1]) ?? 0)
            }
        }

        // Parse status --porcelain into a lookup: filename -> statusCode
        var statusMap: [String: String] = [:]
        for line in statusResult.stdout.components(separatedBy: "\n") where !line.isEmpty {
            guard line.count >= 3 else { continue }
            let index = line.index(line.startIndex, offsetBy: 3)
            let file = String(line[index...])
            let x = String(line[line.startIndex...line.startIndex])
            let y = String(line[line.index(line.startIndex, offsetBy: 1)...line.index(line.startIndex, offsetBy: 1)])
            let code = (y == " " || y == "?") ? (x == "?" ? "??" : x) : y
            statusMap[file] = code
        }

        // Parse diff output into per-file sections
        let diffOutput = diffResult.stdout
        var files: [DiffData.FileDiff] = []

        // Split by "diff --git" boundaries
        let fileSections = diffOutput.components(separatedBy: "diff --git ")
        for section in fileSections {
            guard !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let sectionLines = section.components(separatedBy: "\n")
            guard !sectionLines.isEmpty else { continue }

            // First line is "a/path b/path"
            let headerLine = sectionLines[0]
            let headerParts = headerLine.split(separator: " ", maxSplits: 1)
            var filename = ""
            if headerParts.count >= 2 {
                // Extract from "b/path"
                let bPath = String(headerParts[1])
                filename = bPath.hasPrefix("b/") ? String(bPath.dropFirst(2)) : bPath
            } else if headerParts.count == 1 {
                let aPath = String(headerParts[0])
                filename = aPath.hasPrefix("a/") ? String(aPath.dropFirst(2)) : aPath
            }

            // Parse hunks
            var hunks: [DiffData.Hunk] = []
            var currentHunkHeader = ""
            var currentHunkLines: [DiffData.DiffLine] = []
            var oldLineNo = 0
            var newLineNo = 0
            var inHunk = false

            for lineIdx in 1..<sectionLines.count {
                let line = sectionLines[lineIdx]

                if line.hasPrefix("@@") {
                    // Save previous hunk if any
                    if inHunk && !currentHunkLines.isEmpty {
                        hunks.append(DiffData.Hunk(header: currentHunkHeader, lines: currentHunkLines))
                    }

                    currentHunkHeader = line
                    currentHunkLines = []
                    inHunk = true

                    // Parse line numbers from "@@ -old,count +new,count @@"
                    let scanner = line.dropFirst(3) // drop "@@ "
                    if let plusIdx = scanner.firstIndex(of: "+") {
                        let newPart = scanner[plusIdx...].dropFirst() // drop "+"
                        if let commaOrSpace = newPart.firstIndex(where: { $0 == "," || $0 == " " }) {
                            newLineNo = Int(newPart[newPart.startIndex..<commaOrSpace]) ?? 1
                        } else {
                            newLineNo = Int(newPart) ?? 1
                        }
                    }
                    if let minusIdx = scanner.firstIndex(of: "-") {
                        let oldPart = scanner[scanner.index(after: minusIdx)...]
                        if let commaOrSpace = oldPart.firstIndex(where: { $0 == "," || $0 == " " }) {
                            oldLineNo = Int(oldPart[oldPart.startIndex..<commaOrSpace]) ?? 1
                        } else {
                            oldLineNo = Int(oldPart) ?? 1
                        }
                    }

                    continue
                }

                // Skip metadata lines (index, ---, +++)
                if !inHunk { continue }

                if line.hasPrefix("+") {
                    let content = String(line.dropFirst())
                    currentHunkLines.append(DiffData.DiffLine(
                        type: .addition, content: content,
                        oldLineNo: nil, newLineNo: newLineNo
                    ))
                    newLineNo += 1
                } else if line.hasPrefix("-") {
                    let content = String(line.dropFirst())
                    currentHunkLines.append(DiffData.DiffLine(
                        type: .deletion, content: content,
                        oldLineNo: oldLineNo, newLineNo: nil
                    ))
                    oldLineNo += 1
                } else if line.hasPrefix(" ") {
                    let content = String(line.dropFirst())
                    currentHunkLines.append(DiffData.DiffLine(
                        type: .context, content: content,
                        oldLineNo: oldLineNo, newLineNo: newLineNo
                    ))
                    oldLineNo += 1
                    newLineNo += 1
                } else if line.hasPrefix("\\") {
                    // "\ No newline at end of file" — skip
                    continue
                }
            }

            // Save last hunk
            if inHunk && !currentHunkLines.isEmpty {
                hunks.append(DiffData.Hunk(header: currentHunkHeader, lines: currentHunkLines))
            }

            let stats = numstatMap[filename] ?? (0, 0)
            let statusCode = statusMap[filename] ?? "M"

            files.append(DiffData.FileDiff(
                filename: filename,
                statusCode: statusCode,
                added: stats.0,
                removed: stats.1,
                hunks: hunks
            ))
        }

        // Include files from status that have no diff (e.g. untracked files)
        for (file, code) in statusMap {
            if !files.contains(where: { $0.filename == file }) {
                let stats = numstatMap[file] ?? (0, 0)
                files.append(DiffData.FileDiff(
                    filename: file,
                    statusCode: code,
                    added: stats.0,
                    removed: stats.1,
                    hunks: []
                ))
            }
        }

        return DiffData(files: files)
    }

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = terminalBackground.cgColor

        // Icon
        iconView.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Worktree")
        iconView.contentTintColor = .controlAccentColor
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // Name
        nameLabel.font = .boldSystemFont(ofSize: 18)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        // Branch
        branchLabel.font = .systemFont(ofSize: 13)
        branchLabel.textColor = .secondaryLabelColor
        branchLabel.lineBreakMode = .byTruncatingTail
        branchLabel.translatesAutoresizingMaskIntoConstraints = false

        // Shortcut hint
        shortcutLabel.font = .systemFont(ofSize: 12)
        shortcutLabel.textColor = .tertiaryLabelColor
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false

        // Action buttons
        configureButton(agentButton, title: "Agent", icon: "cpu")
        configureButton(terminalButton, title: "Terminal", icon: "terminal")
        configureButton(worktreeButton, title: "Worktree", icon: "arrow.triangle.branch")

        agentButton.target = self
        agentButton.action = #selector(agentButtonClicked)
        terminalButton.target = self
        terminalButton.action = #selector(terminalButtonClicked)
        worktreeButton.target = self
        worktreeButton.action = #selector(worktreeButtonClicked)

        // Header layout
        let titleStack = NSStackView(views: [nameLabel, branchLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        let buttonStack = NSStackView(views: [shortcutLabel, agentButton, terminalButton, worktreeButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.alignment = .centerY

        let topRow = NSStackView(views: [iconView, titleStack])
        topRow.orientation = .horizontal
        topRow.spacing = 10
        topRow.alignment = .centerY

        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 8
        headerStack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 12, right: 16)
        headerStack.addArrangedSubview(topRow)
        headerStack.addArrangedSubview(buttonStack)
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerStack)

        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        // Empty state label
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true

        // Diff card stack inside scroll view
        diffStackView.orientation = .vertical
        diffStackView.spacing = 12
        diffStackView.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        diffStackView.translatesAutoresizingMaskIntoConstraints = false
        diffStackView.setHuggingPriority(.defaultLow, for: .horizontal)

        scrollView.documentView = diffStackView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = terminalBackground
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: topAnchor),
            headerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: trailingAnchor),

            separator.topAnchor.constraint(equalTo: headerStack.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Stack view width tracks the scroll view's clip view
            diffStackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            diffStackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    private func configureButton(_ button: NSButton, title: String, icon: String) {
        button.bezelStyle = .accessoryBarAction
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
        button.title = title
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 11)
        button.isBordered = false
        button.contentTintColor = terminalForeground
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func agentButtonClicked() { onNewAgent?() }
    @objc private func terminalButtonClicked() { onNewTerminal?() }
    @objc private func worktreeButtonClicked() { onNewWorktree?() }
}

// MARK: - DiffCardView

class DiffCardView: NSView {

    private let fileDiff: WorktreeDetailView.DiffData.FileDiff

    init(fileDiff: WorktreeDetailView.DiffData.FileDiff) {
        self.fileDiff = fileDiff
        super.init(frame: .zero)
        setupCard()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func setupCard() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = WorktreeDetailView.cardBackground.cgColor

        // Header bar
        let headerView = NSView()
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = WorktreeDetailView.cardHeaderBackground.cgColor
        headerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerView)

        // File icon
        let iconName: String
        let iconTint: NSColor
        switch fileDiff.statusCode {
        case "A": iconName = "doc.badge.plus"; iconTint = .systemGreen
        case "D": iconName = "doc.badge.minus"; iconTint = .systemRed
        case "M": iconName = "doc.text"; iconTint = .systemYellow
        default:  iconName = "doc.text"; iconTint = .systemGray
        }
        let fileIcon = NSImageView()
        fileIcon.image = NSImage(systemSymbolName: iconName, accessibilityDescription: fileDiff.statusCode)
        fileIcon.contentTintColor = iconTint
        fileIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        fileIcon.translatesAutoresizingMaskIntoConstraints = false

        // Filename label — directory in secondary, last component bold
        let filenameLabel = NSTextField(labelWithString: "")
        filenameLabel.allowsDefaultTighteningForTruncation = true
        filenameLabel.lineBreakMode = .byTruncatingMiddle
        filenameLabel.translatesAutoresizingMaskIntoConstraints = false
        filenameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let pathComponents = fileDiff.filename.split(separator: "/")
        let filenameAttr = NSMutableAttributedString()
        let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let monoBold = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        if pathComponents.count > 1 {
            let dir = pathComponents.dropLast().joined(separator: "/") + "/"
            filenameAttr.append(NSAttributedString(string: dir, attributes: [
                .font: monoFont,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            filenameAttr.append(NSAttributedString(string: String(pathComponents.last!), attributes: [
                .font: monoBold,
                .foregroundColor: terminalForeground,
            ]))
        } else {
            filenameAttr.append(NSAttributedString(string: fileDiff.filename, attributes: [
                .font: monoBold,
                .foregroundColor: terminalForeground,
            ]))
        }
        filenameLabel.attributedStringValue = filenameAttr

        // Status badge
        let badgeLabel = NSTextField(labelWithString: "")
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        let badgeText: String
        let badgeColor: NSColor
        switch fileDiff.statusCode {
        case "M": badgeText = "Modified"; badgeColor = .systemYellow
        case "A": badgeText = "Added"; badgeColor = .systemGreen
        case "D": badgeText = "Deleted"; badgeColor = .systemRed
        case "??": badgeText = "Untracked"; badgeColor = .systemGray
        default: badgeText = fileDiff.statusCode; badgeColor = .systemGray
        }
        badgeLabel.attributedStringValue = NSAttributedString(string: " \(badgeText) ", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: badgeColor.withAlphaComponent(0.6),
        ])
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.cornerRadius = 3
        badgeLabel.layer?.masksToBounds = true
        badgeLabel.layer?.backgroundColor = badgeColor.withAlphaComponent(0.6).cgColor

        // Stats label
        let statsAttr = NSMutableAttributedString()
        let statsFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        if fileDiff.added > 0 {
            statsAttr.append(NSAttributedString(string: "+\(fileDiff.added)", attributes: [
                .font: statsFont,
                .foregroundColor: WorktreeDetailView.additionText,
            ]))
        }
        if fileDiff.removed > 0 {
            if statsAttr.length > 0 { statsAttr.append(NSAttributedString(string: "  ")) }
            statsAttr.append(NSAttributedString(string: "-\(fileDiff.removed)", attributes: [
                .font: statsFont,
                .foregroundColor: WorktreeDetailView.deletionText,
            ]))
        }
        let statsLabel = NSTextField(labelWithString: "")
        statsLabel.attributedStringValue = statsAttr
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        statsLabel.setContentHuggingPriority(.required, for: .horizontal)
        statsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Header layout
        headerView.addSubview(fileIcon)
        headerView.addSubview(filenameLabel)
        headerView.addSubview(badgeLabel)
        headerView.addSubview(statsLabel)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 32),

            fileIcon.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 10),
            fileIcon.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            fileIcon.widthAnchor.constraint(equalToConstant: 16),
            fileIcon.heightAnchor.constraint(equalToConstant: 16),

            filenameLabel.leadingAnchor.constraint(equalTo: fileIcon.trailingAnchor, constant: 6),
            filenameLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            badgeLabel.leadingAnchor.constraint(equalTo: filenameLabel.trailingAnchor, constant: 8),
            badgeLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            statsLabel.leadingAnchor.constraint(greaterThanOrEqualTo: badgeLabel.trailingAnchor, constant: 8),
            statsLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -10),
            statsLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
        ])

        // Body — diff lines
        if fileDiff.hunks.isEmpty {
            // No diff content (e.g. untracked file) — just show header
            bottomAnchor.constraint(equalTo: headerView.bottomAnchor).isActive = true
            return
        }

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = WorktreeDetailView.cardBackground
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.autoresizingMask = [.width]
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)

        let attributed = buildDiffAttributedString()
        textView.textStorage?.setAttributedString(attributed)

        // Compute height from attributed string
        let tempContainer = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        let tempLayout = NSLayoutManager()
        let tempStorage = NSTextStorage(attributedString: attributed)
        tempLayout.addTextContainer(tempContainer)
        tempStorage.addLayoutManager(tempLayout)
        tempLayout.ensureLayout(for: tempContainer)
        let textHeight = tempLayout.usedRect(for: tempContainer).height + 12 // padding

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            textView.heightAnchor.constraint(equalToConstant: textHeight),
        ])
    }

    private func buildDiffAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let lineNoFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

        // Tab stops for gutter: old line no at 0, new line no at 40, code at 90
        let tabStops = [
            NSTextTab(textAlignment: .right, location: 36),
            NSTextTab(textAlignment: .right, location: 72),
            NSTextTab(textAlignment: .left, location: 82),
        ]

        for (hunkIdx, hunk) in fileDiff.hunks.enumerated() {
            // Hunk separator (between hunks, not before the first)
            if hunkIdx > 0 {
                let sepPara = NSMutableParagraphStyle()
                sepPara.alignment = .center
                sepPara.paragraphSpacingBefore = 4
                sepPara.paragraphSpacing = 4
                result.append(NSAttributedString(string: "···\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .paragraphStyle: sepPara,
                    .backgroundColor: WorktreeDetailView.hunkSeparatorColor,
                ]))
            }

            for line in hunk.lines {
                let para = NSMutableParagraphStyle()
                para.tabStops = tabStops

                let bgColor: NSColor
                let fgColor: NSColor
                switch line.type {
                case .addition:
                    bgColor = WorktreeDetailView.additionBackground
                    fgColor = WorktreeDetailView.additionText
                case .deletion:
                    bgColor = WorktreeDetailView.deletionBackground
                    fgColor = WorktreeDetailView.deletionText
                case .context:
                    bgColor = WorktreeDetailView.cardBackground
                    fgColor = terminalForeground
                }

                // Old line number
                let oldNo = line.oldLineNo.map { String($0) } ?? ""
                result.append(NSAttributedString(string: "\t\(oldNo)", attributes: [
                    .font: lineNoFont,
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .backgroundColor: bgColor,
                    .paragraphStyle: para,
                ]))

                // New line number
                let newNo = line.newLineNo.map { String($0) } ?? ""
                result.append(NSAttributedString(string: "\t\(newNo)", attributes: [
                    .font: lineNoFont,
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .backgroundColor: bgColor,
                ]))

                // Code content
                result.append(NSAttributedString(string: "\t\(line.content)\n", attributes: [
                    .font: monoFont,
                    .foregroundColor: fgColor,
                    .backgroundColor: bgColor,
                ]))
            }
        }

        return result
    }
}
