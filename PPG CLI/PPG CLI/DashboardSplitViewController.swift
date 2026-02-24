import AppKit

class DashboardSplitViewController: NSSplitViewController {
    let sidebar = SidebarViewController()
    let content = ContentViewController()

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
    private func collectAllTerminalIds() -> Set<String> {
        var ids = Set<String>()
        for projectNode in sidebar.projectNodes {
            guard case .project(let ctx) = projectNode.item else { continue }
            let worktrees = sidebar.worktrees(for: ctx)
            for wt in worktrees {
                for agent in wt.agents {
                    ids.insert(agent.id)
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

    // MARK: - Selection & Refresh

    private func handleSelection(_ item: SidebarItem) {
        switch item {
        case .worktree(let wt):
            guard let ctx = sidebar.projectContext(for: item) else {
                content.showEntry(nil)
                break
            }
            content.showWorktreeDetail(
                worktree: wt,
                projectRoot: ctx.projectRoot,
                onNewAgent: { [weak self] in self?.addAgent(project: ctx, parentWorktreeId: wt.id) },
                onNewTerminal: { [weak self] in self?.addTerminal(project: ctx, parentWorktreeId: wt.id) },
                onNewWorktree: { [weak self] in self?.createWorktree(project: ctx) }
            )
        default:
            content.showEntry(tabEntry(for: item))
        }
        updateWindowTitle(for: item)
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
        guard let item = currentItem else { return }

        // If a worktree is selected and its detail view is showing, refresh the diff
        if case .worktree = item, content.isShowingWorktreeDetail {
            content.refreshWorktreeDetail()
            // Still clean stale cached views
            let validIds = collectAllTerminalIds()
            content.clearStaleViews(validIds: validIds)
            return
        }

        let entry = tabEntry(for: item)

        if let entry = entry, let currentId = content.currentEntryId, entry.id == currentId {
            // Same entry — just update status
            content.updateCurrentEntry(entry)
        } else if entry != nil {
            // Different entry or entry appeared — re-show
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
