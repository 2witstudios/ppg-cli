import AppKit

class DashboardSplitViewController: NSSplitViewController {
    let sidebar = SidebarViewController()
    let content = ContentViewController()

    /// Coalesces rapid handleRefresh calls into a single main-thread pass.
    private var pendingRefreshWork: DispatchWorkItem?
    private let refreshCoalesceDelay: TimeInterval = 0.05  // 50ms

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 300
        addSplitViewItem(sidebarItem)

        let contentItem = NSSplitViewItem(viewController: content)
        contentItem.automaticallyAdjustsSafeAreaInsets = true
        addSplitViewItem(contentItem)

        sidebar.onItemSelected = { [weak self] item in
            self?.handleSelection(item)
        }

        sidebar.onAddAgent = { [weak self] project, worktreeId in
            self?.addAgent(project: project, parentWorktreeId: worktreeId)
        }

        sidebar.onAddTerminal = { [weak self] project, worktreeId in
            self?.addTerminal(project: project, parentWorktreeId: worktreeId)
        }

        sidebar.onAddWorktree = { [weak self] project in
            self?.createWorktree(project: project)
        }

        sidebar.onDataRefreshed = { [weak self] currentItem in
            self?.handleRefresh(currentItem)
        }

        sidebar.onRenameTerminal = { [weak self] project, id, newLabel in
            guard let self = self else { return }
            project.dashboardSession.rename(id: id, newLabel: newLabel)
            self.sidebar.refresh()
        }

        sidebar.onDeleteTerminal = { [weak self] project, id in
            guard let self = self else { return }
            if let entry = project.dashboardSession.entry(byId: id),
               let tmuxTarget = entry.tmuxTarget {
                project.dashboardSession.killTmuxWindow(target: tmuxTarget)
            }
            self.content.removeEntry(byId: id)
            project.dashboardSession.remove(id: id)
            self.sidebar.refresh()
        }

        sidebar.onRenameAgent = { [weak self] project, agentId, newName in
            guard let self = self else { return }
            self.renameManifestAgent(project: project, agentId: agentId, newName: newName)
        }

        sidebar.onDeleteAgent = { [weak self] project, agentId in
            guard let self = self else { return }
            self.deleteManifestAgent(project: project, agentId: agentId)
        }

        sidebar.onDeleteWorktree = { [weak self] project, worktreeId in
            guard let self = self else { return }
            self.deleteWorktree(project: project, worktreeId: worktreeId)
        }

        sidebar.onSettingsClicked = { [weak self] in
            self?.showSettings()
        }

        sidebar.onAddProject = {
            guard let delegate = NSApp.delegate as? AppDelegate else { return }
            delegate.openProject()
        }

        sidebar.onDashboardClicked = { [weak self] in
            self?.showHomeDashboard()
        }

        sidebar.onSwarmsClicked = { [weak self] in
            self?.showSwarmsView()
        }

        sidebar.onPromptsClicked = { [weak self] in
            self?.showPromptsView()
        }

        // Save grid layout when a grid is suspended (navigate away)
        content.onGridSuspended = { [weak self] ownerEntryId, layout in
            guard let self = self else { return }
            for projectNode in self.sidebar.projectNodes {
                guard case .project(let ctx) = projectNode.item else { continue }
                if !ctx.dashboardSession.entriesForGrid(ownerEntryId: ownerEntryId).isEmpty {
                    ctx.dashboardSession.saveGridLayout(ownerEntryId: ownerEntryId, layout: layout)
                    return
                }
            }
        }

        // Clean up persisted grid-owned session entries when a grid is destroyed
        content.onGridDestroyed = { [weak self] ownerEntryId in
            guard let self = self else { return }
            for projectNode in self.sidebar.projectNodes {
                guard case .project(let ctx) = projectNode.item else { continue }
                let gridEntries = ctx.dashboardSession.entriesForGrid(ownerEntryId: ownerEntryId)
                for gridEntry in gridEntries {
                    if let tmuxTarget = gridEntry.tmuxTarget {
                        ctx.dashboardSession.killTmuxWindow(target: tmuxTarget)
                    }
                    ctx.dashboardSession.remove(id: gridEntry.id)
                }
                ctx.dashboardSession.removeGridLayout(ownerEntryId: ownerEntryId)
            }
        }

        // Auto-show dashboard on launch
        DispatchQueue.main.async { [weak self] in
            self?.showHomeDashboard()
        }
    }

    private func showSettings() {
        let settingsVC = SettingsViewController()
        presentAsSheet(settingsVC)
    }

    // MARK: - Single Entry Conversion

    /// Convert a sidebar item to a single TabEntry, or nil for container items.
    private func tabEntry(for item: SidebarItem) -> TabEntry? {
        guard let ctx = sidebar.projectContext(for: item) else { return nil }
        let sessionName = ctx.sessionName

        switch item {
        case .project, .worktree:
            return nil

        case .agent(let ag):
            // Check if this agent shares a tmux window with others
            let worktrees = sidebar.worktrees(for: ctx)
            if let wt = worktrees.first(where: { $0.agents.contains(where: { a in a.id == ag.id }) }) {
                let target = ag.tmuxTarget
                let windowKey: String
                if let dotIndex = target.lastIndex(of: ".") {
                    windowKey = String(target[target.startIndex..<dotIndex])
                } else {
                    windowKey = target
                }
                let sharing = wt.agents.filter { a in
                    let t = a.tmuxTarget
                    if let d = t.lastIndex(of: ".") {
                        return String(t[t.startIndex..<d]) == windowKey
                    }
                    return t == windowKey
                }
                if sharing.count > 1 {
                    return .agentGroup(sharing, windowKey, sessionName: sessionName)
                }
            }
            return .manifestAgent(ag, sessionName: sessionName)

        case .agentGroup(let agents, let windowKey):
            return .agentGroup(agents, windowKey, sessionName: sessionName)

        case .terminal(let entry):
            return .sessionEntry(entry, sessionName: sessionName)
        }
    }

    /// Collect all terminal/agent IDs across the sidebar tree for cache cleanup.
    /// Includes compound agentGroup IDs ("id1+id2") for agents sharing a tmux window.
    private func collectAllTerminalIds() -> Set<String> {
        var ids = Set<String>()
        for projectNode in sidebar.projectNodes {
            guard case .project(let ctx) = projectNode.item else { continue }
            let worktrees = sidebar.worktrees(for: ctx)
            for wt in worktrees {
                // Build a lookup of tmux window key -> agents sharing that window
                var windowAgents: [String: [AgentModel]] = [:]
                for agent in wt.agents {
                    ids.insert(agent.id)
                    let target = agent.tmuxTarget
                    let windowKey: String
                    if let dotIndex = target.lastIndex(of: ".") {
                        windowKey = String(target[target.startIndex..<dotIndex])
                    } else {
                        windowKey = target
                    }
                    windowAgents[windowKey, default: []].append(agent)
                }
                // Add compound IDs for agent groups sharing a tmux window
                for (_, agents) in windowAgents where agents.count > 1 {
                    ids.insert(agents.map(\.id).joined(separator: "+"))
                }
                for entry in ctx.dashboardSession.entriesForWorktree(wt.id) {
                    ids.insert(entry.id)
                }
            }
            for entry in ctx.dashboardSession.entriesForMaster() {
                ids.insert(entry.id)
            }
        }
        return ids
    }

    /// Cmd+W handler: close/kill the currently displayed entry.
    func closeCurrentEntry() {
        // In grid mode, Cmd+W closes the focused pane (same as Cmd+Shift+W).
        if content.isGridMode {
            _ = content.closeFocusedPane()
            return
        }

        guard let entryId = content.currentEntryId else { return }

        // Try to find which project owns this entry
        for projectNode in sidebar.projectNodes {
            guard case .project(let ctx) = projectNode.item else { continue }

            // Check dashboard session entries
            if let entry = ctx.dashboardSession.entry(byId: entryId) {
                if let tmuxTarget = entry.tmuxTarget {
                    ctx.dashboardSession.killTmuxWindow(target: tmuxTarget)
                }
                content.removeEntry(byId: entryId)
                ctx.dashboardSession.remove(id: entryId)
                sidebar.refresh()
                return
            }

            // Check manifest agents
            let worktrees = sidebar.worktrees(for: ctx)
            for wt in worktrees {
                if wt.agents.contains(where: { $0.id == entryId }) {
                    deleteManifestAgent(project: ctx, agentId: entryId)
                    return
                }
            }
        }

        // Fallback: just remove the view
        content.removeEntry(byId: entryId)
    }

    // MARK: - Grid Restoration

    /// Rebuild a grid from persisted session entries after a reboot.
    /// Uses the saved layout tree to preserve split directions and ratios.
    private func rebuildGridFromSession(entry: TabEntry, project: ProjectContext) {
        let gridEntries = project.dashboardSession.entriesForGrid(ownerEntryId: entry.id)
        guard !gridEntries.isEmpty else { return }

        let sessionName = project.sessionName
        let savedLayout = project.dashboardSession.gridLayout(forOwnerEntryId: entry.id)

        wireGridCallbacks()
        content.splitPaneRight()

        guard let grid = content.paneGrid else { return }

        if let layout = savedLayout {
            // Rebuild the tree from the saved layout, then fill leaves with entries
            var counter = PaneGridController.leafIdCounter
            let restoredRoot = PaneSplitNode.fromLayoutNode(layout, idGenerator: &counter)
            PaneGridController.leafIdCounter = counter

            grid.replaceRoot(restoredRoot)

            // Build a lookup from entry ID -> session entry
            var entryById: [String: DashboardSession.TerminalEntry] = [:]
            for ge in gridEntries { entryById[ge.id] = ge }

            // Walk the layout and restored tree in parallel to fill entries
            fillLeavesFromLayout(grid: grid, layout: layout, leafIds: restoredRoot.allLeafIds(), sessionName: sessionName, ownerEntry: entry, entryById: entryById)
        } else {
            // No saved layout — fall back to simple vertical splits
            content.paneGrid?.fillFocusedPane(with: .sessionEntry(gridEntries[0], sessionName: sessionName))
            for i in 1..<gridEntries.count {
                grid.splitFocusedPane(direction: .vertical)
                grid.fillFocusedPane(with: .sessionEntry(gridEntries[i], sessionName: sessionName))
            }
        }

        // Focus back to the first pane
        if let firstLeaf = grid.root.allLeafIds().first {
            grid.setFocus(firstLeaf)
        }
    }

    /// Walk the layout tree and the matching leaf IDs to fill each pane with the right entry.
    private func fillLeavesFromLayout(
        grid: PaneGridController,
        layout: GridLayoutNode,
        leafIds: [String],
        sessionName: String,
        ownerEntry: TabEntry,
        entryById: [String: DashboardSession.TerminalEntry]
    ) {
        // Collect entry IDs from the layout in tree order (depth-first)
        let layoutEntryIds = collectLeafEntryIds(from: layout)

        for (i, leafId) in leafIds.enumerated() {
            guard i < layoutEntryIds.count else { break }
            let entryId = layoutEntryIds[i]

            if let entryId = entryId {
                if entryId == ownerEntry.id {
                    // This is the grid owner — show it directly
                    grid.setFocus(leafId)
                    grid.fillFocusedPane(with: ownerEntry)
                } else if let sessionEntry = entryById[entryId] {
                    grid.setFocus(leafId)
                    grid.fillFocusedPane(with: .sessionEntry(sessionEntry, sessionName: sessionName))
                }
            }
        }
    }

    /// Depth-first collection of entry IDs from a layout tree.
    private func collectLeafEntryIds(from node: GridLayoutNode) -> [String?] {
        if node.isLeaf {
            return [node.entryId]
        }
        guard let children = node.children, children.count == 2 else { return [] }
        return collectLeafEntryIds(from: children[0]) + collectLeafEntryIds(from: children[1])
    }

    /// Persist the current grid layout to the dashboard session on disk.
    private func persistGridLayout() {
        guard let grid = content.paneGrid, let ownerId = content.activeGridOwnerId else { return }
        let layout = grid.root.toLayoutNode()
        if let ctx = projectContextForGridOwner(ownerId) {
            ctx.dashboardSession.saveGridLayout(ownerEntryId: ownerId, layout: layout)
        }
    }

    /// Find the project context that owns an entry by ID.
    private func projectContextForGridOwner(_ entryId: String) -> ProjectContext? {
        for projectNode in sidebar.projectNodes {
            guard case .project(let ctx) = projectNode.item else { continue }
            // Check dashboard session entries
            if ctx.dashboardSession.entry(byId: entryId) != nil { return ctx }
            // Check manifest agents
            let worktrees = sidebar.worktrees(for: ctx)
            for wt in worktrees {
                if wt.agents.contains(where: { $0.id == entryId }) { return ctx }
            }
            // Check if this entry has grid children in this project
            if !ctx.dashboardSession.entriesForGrid(ownerEntryId: entryId).isEmpty { return ctx }
        }
        return sidebar.selectedProjectContext()
    }

    // MARK: - Pane Grid Actions

    func splitPaneBelow() {
        guard content.currentEntryId != nil || content.isGridMode else { return }
        wireGridCallbacks()
        content.splitPaneBelow()
        persistGridLayout()
    }

    func splitPaneRight() {
        guard content.currentEntryId != nil || content.isGridMode else { return }
        wireGridCallbacks()
        content.splitPaneRight()
        persistGridLayout()
    }

    func closeFocusedPane() {
        guard content.isGridMode else { return }
        _ = content.closeFocusedPane()
        persistGridLayout()
    }

    func movePaneFocus(direction: SplitDirection, forward: Bool) {
        guard content.isGridMode else { return }
        content.movePaneFocus(direction: direction, forward: forward)
    }

    /// Set up grid controller callbacks for picker actions.
    /// Callbacks resolve the current project context at invocation time (not wire time)
    /// so they stay correct when the user switches projects.
    private func wireGridCallbacks() {
        let grid = content.ensureGridController()

        // Only wire once
        guard grid.onNewAgent == nil else { return }

        grid.onNewAgent = { [weak self] in
            guard let self = self else { return }
            // Resolve project context now — not at wire time
            guard let ctx = self.sidebar.selectedProjectContext() else { return }
            let worktreeId = self.sidebar.selectedWorktreeId()
            self.addAgentToGrid(project: ctx, parentWorktreeId: worktreeId)
        }

        grid.onNewTerminal = { [weak self] in
            guard let self = self else { return }
            guard let ctx = self.sidebar.selectedProjectContext() else { return }
            let worktreeId = self.sidebar.selectedWorktreeId()
            self.addTerminalToGrid(project: ctx, parentWorktreeId: worktreeId)
        }

        grid.onPickFromSidebar = { [weak self] in
            guard let self = self else { return }
            self.sidebar.view.window?.makeFirstResponder(self.sidebar.view)
        }

        grid.onSplitPane = { [weak self] leafId, direction in
            guard let self = self, let grid = self.content.paneGrid else { return }
            grid.setFocus(leafId)
            grid.splitFocusedPane(direction: direction)
            self.persistGridLayout()
        }

        grid.onClosePane = { [weak self] leafId in
            guard let self = self, let grid = self.content.paneGrid else { return }
            grid.setFocus(leafId)
            if grid.root.leafCount <= 1 {
                self.content.exitGridMode()
            } else {
                _ = grid.closeFocusedPane()
                self.persistGridLayout()
            }
        }
    }

    /// Add agent and fill the focused grid pane.
    private func addAgentToGrid(project: ProjectContext, parentWorktreeId: String?) {
        guard let gridOwnerId = content.activeGridOwnerId else { return }
        let workingDir = workingDirectory(project: project, worktreeId: parentWorktreeId)
        let entry = project.dashboardSession.addAgent(
            sessionName: project.sessionName,
            parentWorktreeId: parentWorktreeId,
            command: project.agentCommand,
            workingDir: workingDir
        )
        // Mark as grid-owned so it persists but doesn't appear in the sidebar.
        project.dashboardSession.setGridOwner(entryId: entry.id, gridOwnerEntryId: gridOwnerId)
        content.paneGrid?.fillFocusedPane(with: .sessionEntry(entry, sessionName: project.sessionName))
        persistGridLayout()
    }

    /// Add terminal and fill the focused grid pane.
    private func addTerminalToGrid(project: ProjectContext, parentWorktreeId: String?) {
        guard let gridOwnerId = content.activeGridOwnerId else { return }
        let workingDir = workingDirectory(project: project, worktreeId: parentWorktreeId)
        let entry = project.dashboardSession.addTerminal(
            parentWorktreeId: parentWorktreeId,
            workingDir: workingDir
        )
        // Mark as grid-owned so it persists but doesn't appear in the sidebar.
        project.dashboardSession.setGridOwner(entryId: entry.id, gridOwnerEntryId: gridOwnerId)
        content.paneGrid?.fillFocusedPane(with: .sessionEntry(entry, sessionName: project.sessionName))
        persistGridLayout()
    }

    // MARK: - Home Dashboard

    func showHomeDashboard() {
        let projects = OpenProjects.shared.projects
        content.showHomeDashboard(projects: projects, worktreesByProject: sidebar.projectWorktrees)
        view.window?.title = "ppg"
    }

    func showSwarmsView() {
        let projects = OpenProjects.shared.projects
        content.showSwarmsView(projects: projects)
        view.window?.title = "ppg - Swarms"
    }

    func showPromptsView() {
        let projects = OpenProjects.shared.projects
        content.showPromptsView(projects: projects)
        view.window?.title = "ppg - Prompts"
    }

    // MARK: - Selection & Refresh

    private func handleSelection(_ item: SidebarItem) {
        switch item {
        case .project(let ctx):
            showProjectDetail(ctx: ctx, worktreeId: nil)
        case .worktree(let wt):
            guard let ctx = sidebar.projectContext(for: item) else {
                content.showEntry(nil)
                break
            }
            showProjectDetail(ctx: ctx, worktreeId: wt.id)
        default:
            let entry = tabEntry(for: item)
            guard let entry = entry else { break }
            // Does this entry own a saved grid? Restore it.
            if content.restoreGrid(forEntryId: entry.id) {
                // Grid restored — done
            } else if let ctx = sidebar.projectContext(for: item),
                      !ctx.dashboardSession.entriesForGrid(ownerEntryId: entry.id).isEmpty {
                // Persisted grid children exist (e.g. after reboot) — rebuild the grid
                content.showEntry(entry)
                rebuildGridFromSession(entry: entry, project: ctx)
            } else {
                // Normal single-pane navigation (suspendGrid happens inside showEntry)
                content.showEntry(entry)
            }
        }
        updateWindowTitle(for: item)
    }

    private func showProjectDetail(ctx: ProjectContext, worktreeId: String?) {
        let worktrees = sidebar.worktrees(for: ctx)
        let wt: WorktreeModel
        if let wtId = worktreeId, let found = worktrees.first(where: { $0.id == wtId }) {
            wt = found
        } else {
            // Synthetic worktree model for the project root
            wt = WorktreeModel(
                id: "__project__",
                name: ctx.projectName,
                path: ctx.projectRoot,
                branch: currentBranch(at: ctx.projectRoot),
                status: "active",
                tmuxWindow: "",
                agents: []
            )
        }
        content.showWorktreeDetail(
            worktree: wt,
            projectRoot: ctx.projectRoot,
            onNewAgent: { [weak self] in self?.addAgent(project: ctx, parentWorktreeId: worktreeId) },
            onNewTerminal: { [weak self] in self?.addTerminal(project: ctx, parentWorktreeId: worktreeId) },
            onNewWorktree: { [weak self] in self?.createWorktree(project: ctx) }
        )
    }

    private func currentBranch(at path: String) -> String {
        PPGService.shared.currentBranch(at: path)
    }

    private func updateWindowTitle(for item: SidebarItem) {
        switch item {
        case .project(let ctx):
            view.window?.title = ctx.projectName
        case .worktree(let wt):
            view.window?.title = wt.name
        case .agent(let ag):
            view.window?.title = ag.name.isEmpty ? ag.id : ag.name
        case .agentGroup(let agents, _):
            view.window?.title = "\(agents.count) agents (split)"
        case .terminal(let entry):
            view.window?.title = entry.label
        }
    }

    private func handleRefresh(_ currentItem: SidebarItem?) {
        // Cancel any pending coalesced refresh — we'll schedule a new one
        pendingRefreshWork?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.performRefresh(currentItem)
        }
        pendingRefreshWork = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + refreshCoalesceDelay, execute: workItem)
    }

    /// Actual refresh logic, invoked after coalescing delay.
    private func performRefresh(_ currentItem: SidebarItem?) {
        // If prompts or swarms view is visible, just clean stale views
        if content.isShowingPromptsView || content.isShowingSwarmsView {
            let validIds = collectAllTerminalIds()
            content.clearStaleViews(validIds: validIds)
            return
        }

        // If the home dashboard is visible, refresh it
        if content.isShowingHomeDashboard {
            let projects = OpenProjects.shared.projects
            content.refreshHomeDashboard(projects: projects, worktreesByProject: sidebar.projectWorktrees)
            let validIds = collectAllTerminalIds()
            content.clearStaleViews(validIds: validIds)
            return
        }

        guard let item = currentItem else { return }

        // If a project or worktree is selected and its detail view is showing, refresh the diff
        let isDetailItem: Bool
        switch item {
        case .project, .worktree: isDetailItem = true
        default: isDetailItem = false
        }
        if isDetailItem, content.isShowingWorktreeDetail {
            content.refreshWorktreeDetail()
            let validIds = collectAllTerminalIds()
            content.clearStaleViews(validIds: validIds)
            return
        }

        let entry = tabEntry(for: item)

        // In grid mode, only update status on entries already visible in the grid — never
        // call showEntry() which would auto-fill or steal pane content.
        if content.isGridMode {
            if let entry = entry, let grid = content.paneGrid, grid.containsEntry(id: entry.id) {
                grid.updateEntry(entry)
            }
        } else if let entry = entry, let currentId = content.currentEntryId, entry.id == currentId {
            // Same entry — just update status
            content.updateCurrentEntry(entry)
        } else if entry != nil, !content.isGridMode {
            // Different entry or entry appeared — re-show (only in single-pane mode)
            content.showEntry(entry)
        }
        // else entry is nil (container) — leave content as-is

        // Clean stale cached views
        let validIds = collectAllTerminalIds()
        content.clearStaleViews(validIds: validIds)
    }

    // MARK: - Add Agent / Terminal / Worktree

    private func addAgent(project: ProjectContext, parentWorktreeId: String?) {
        let workingDir = workingDirectory(project: project, worktreeId: parentWorktreeId)
        let entry = project.dashboardSession.addAgent(
            sessionName: project.sessionName,
            parentWorktreeId: parentWorktreeId,
            command: project.agentCommand,
            workingDir: workingDir
        )
        content.showEntry(.sessionEntry(entry, sessionName: project.sessionName))
        sidebar.refresh()
    }

    private func addTerminal(project: ProjectContext, parentWorktreeId: String?) {
        let workingDir = workingDirectory(project: project, worktreeId: parentWorktreeId)
        let entry = project.dashboardSession.addTerminal(
            parentWorktreeId: parentWorktreeId,
            workingDir: workingDir
        )
        content.showEntry(.sessionEntry(entry, sessionName: project.sessionName))
        sidebar.refresh()
    }

    private func createWorktree(project: ProjectContext) {
        let alert = NSAlert()
        alert.messageText = "New Worktree"
        alert.informativeText = "Enter a name for the worktree:"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "feature-name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let projectRoot = project.projectRoot
        guard !projectRoot.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = PPGService.shared.runPPGCommand("worktree create --name \(shellEscape(name)) --json", projectRoot: projectRoot)

            DispatchQueue.main.async {
                guard let self = self else { return }
                if result.exitCode == 0 {
                    self.sidebar.refresh()
                } else {
                    let errAlert = NSAlert()
                    errAlert.messageText = "Failed to Create Worktree"
                    errAlert.informativeText = result.stderr.isEmpty ? result.stdout : result.stderr
                    errAlert.alertStyle = .warning
                    errAlert.runModal()
                }
            }
        }
    }

    private func renameManifestAgent(project: ProjectContext, agentId: String, newName: String) {
        let manifestPath = project.manifestPath
        guard let data = FileManager.default.contents(atPath: manifestPath),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var worktrees = json["worktrees"] as? [String: Any] else { return }

        for (wtId, wtValue) in worktrees {
            guard var wt = wtValue as? [String: Any],
                  var agents = wt["agents"] as? [String: Any],
                  var agent = agents[agentId] as? [String: Any] else { continue }
            agent["name"] = newName
            agents[agentId] = agent
            wt["agents"] = agents
            worktrees[wtId] = wt
            json["worktrees"] = worktrees
            json["updatedAt"] = ISO8601DateFormatter().string(from: Date())

            if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
                try? updatedData.write(to: URL(fileURLWithPath: manifestPath))
            }
            break
        }

        sidebar.refresh()
    }

    private func deleteManifestAgent(project: ProjectContext, agentId: String) {
        let projectRoot = project.projectRoot
        guard !projectRoot.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = PPGService.shared.runPPGCommand("kill --agent \(shellEscape(agentId)) --delete --json", projectRoot: projectRoot)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if result.exitCode != 0 {
                    let alert = NSAlert()
                    alert.messageText = "Failed to Delete Agent"
                    alert.informativeText = result.stderr.isEmpty ? result.stdout : result.stderr
                    alert.alertStyle = .warning
                    alert.runModal()
                }
                self.content.removeEntry(byId: agentId)
                self.sidebar.refresh()
            }
        }
    }

    private func deleteWorktree(project: ProjectContext, worktreeId: String) {
        let projectRoot = project.projectRoot
        guard !projectRoot.isEmpty else { return }

        // Collect agent IDs belonging to this worktree so we can clean up content views
        let worktrees = sidebar.worktrees(for: project)
        let agentIds = worktrees.first(where: { $0.id == worktreeId })?.agents.map(\.id) ?? []

        // Collect dashboard session entries parented to this worktree
        let sessionEntryIds = project.dashboardSession.entriesForWorktree(worktreeId).map(\.id)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = PPGService.shared.runPPGCommand("kill --worktree \(shellEscape(worktreeId)) --delete --json", projectRoot: projectRoot)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if result.exitCode != 0 {
                    let alert = NSAlert()
                    alert.messageText = "Failed to Delete Worktree"
                    alert.informativeText = result.stderr.isEmpty ? result.stdout : result.stderr
                    alert.alertStyle = .warning
                    alert.runModal()
                }
                // Remove content views for all agents in the worktree
                for id in agentIds {
                    self.content.removeEntry(byId: id)
                }
                // Remove content views for dashboard session entries parented to this worktree
                for id in sessionEntryIds {
                    if let entry = project.dashboardSession.entry(byId: id),
                       let tmuxTarget = entry.tmuxTarget {
                        project.dashboardSession.killTmuxWindow(target: tmuxTarget)
                    }
                    self.content.removeEntry(byId: id)
                    project.dashboardSession.remove(id: id)
                }
                self.sidebar.refresh()
            }
        }
    }

    private func workingDirectory(project: ProjectContext, worktreeId: String?) -> String {
        if let wtId = worktreeId {
            let worktrees = sidebar.worktrees(for: project)
            if let wt = worktrees.first(where: { $0.id == wtId }) {
                return wt.path
            }
        }
        let root = project.projectRoot
        if !root.isEmpty, root != "/" { return root }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// Show creation menu scoped to current sidebar selection's project.
    func showCreationMenu() {
        guard let ctx = sidebar.selectedProjectContext() else { return }
        let worktreeId = sidebar.selectedWorktreeId()

        let menu = NSMenu()

        let worktreeItem = NSMenuItem(title: "New Worktree", action: nil, keyEquivalent: "")
        worktreeItem.target = self
        menu.addItem(worktreeItem)
        menu.addItem(.separator())

        let agentItem = NSMenuItem(title: "New Agent", action: nil, keyEquivalent: "")
        agentItem.target = self
        menu.addItem(agentItem)

        let termItem = NSMenuItem(title: "New Terminal", action: nil, keyEquivalent: "")
        termItem.target = self
        menu.addItem(termItem)

        // Use action blocks via menu item targets
        worktreeItem.action = #selector(creationMenuWorktree(_:))
        worktreeItem.representedObject = ctx
        agentItem.action = #selector(creationMenuAgent(_:))
        agentItem.representedObject = [ctx, worktreeId as Any] as [Any]
        termItem.action = #selector(creationMenuTerminal(_:))
        termItem.representedObject = [ctx, worktreeId as Any] as [Any]

        // Pop up near the center of the window
        if let window = view.window {
            let point = NSPoint(x: window.frame.width / 2, y: window.frame.height / 2)
            menu.popUp(positioning: nil, at: view.convert(point, from: nil), in: view)
        }
    }

    @objc private func creationMenuWorktree(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? ProjectContext else { return }
        createWorktree(project: ctx)
    }

    @objc private func creationMenuAgent(_ sender: NSMenuItem) {
        guard let arr = sender.representedObject as? [Any],
              let ctx = arr.first as? ProjectContext else { return }
        let worktreeId = arr.count > 1 ? arr[1] as? String : nil
        addAgent(project: ctx, parentWorktreeId: worktreeId)
    }

    @objc private func creationMenuTerminal(_ sender: NSMenuItem) {
        guard let arr = sender.representedObject as? [Any],
              let ctx = arr.first as? ProjectContext else { return }
        let worktreeId = arr.count > 1 ? arr[1] as? String : nil
        addTerminal(project: ctx, parentWorktreeId: worktreeId)
    }
}
