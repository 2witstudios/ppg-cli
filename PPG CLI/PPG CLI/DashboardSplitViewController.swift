import AppKit

class DashboardSplitViewController: NSSplitViewController {
    let sidebar = SidebarViewController()
    let content = ContentTabViewController()

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
            self.content.updateTabLabel(id: id, newLabel: newLabel, session: project.dashboardSession)
            self.sidebar.refresh()
        }

        sidebar.onDeleteTerminal = { [weak self] project, id in
            guard let self = self else { return }
            if let entry = project.dashboardSession.entry(byId: id),
               let tmuxTarget = entry.tmuxTarget {
                project.dashboardSession.killTmuxWindow(target: tmuxTarget)
            }
            self.content.removeTab(byId: id)
            project.dashboardSession.remove(id: id)
            self.sidebar.refresh()
        }

        sidebar.onRenameAgent = { [weak self] project, agentId, newName in
            guard let self = self else { return }
            self.renameManifestAgent(project: project, agentId: agentId, newName: newName)
        }

        sidebar.onKillAgent = { [weak self] project, agentId in
            guard let self = self else { return }
            self.killManifestAgent(project: project, agentId: agentId)
        }
    }

    /// Compute the tabs for a given sidebar item.
    private func computeTabs(for item: SidebarItem) -> [TabEntry] {
        guard let ctx = sidebar.projectContext(for: item) else { return [] }
        let session = ctx.dashboardSession
        let sessionName = ctx.sessionName

        switch item {
        case .project:
            return session.entriesForMaster().map { TabEntry.sessionEntry($0, sessionName: sessionName) }

        case .worktree(let wt):
            let manifestTabs = groupedAgentTabs(wt.agents, sessionName: sessionName)
            let dashTabs = session.entriesForWorktree(wt.id).map { TabEntry.sessionEntry($0, sessionName: sessionName) }
            return manifestTabs + dashTabs

        case .agent(let ag):
            let worktrees = sidebar.worktrees(for: ctx)
            if let wt = worktrees.first(where: { $0.agents.contains(where: { a in a.id == ag.id }) }) {
                let manifestTabs = groupedAgentTabs(wt.agents, sessionName: sessionName)
                let dashTabs = session.entriesForWorktree(wt.id).map { TabEntry.sessionEntry($0, sessionName: sessionName) }
                return manifestTabs + dashTabs
            }
            return [.manifestAgent(ag, sessionName: sessionName)]

        case .terminal(let entry):
            let worktrees = sidebar.worktrees(for: ctx)
            if let worktreeId = entry.parentWorktreeId,
               let wt = worktrees.first(where: { $0.id == worktreeId }) {
                let manifestTabs = groupedAgentTabs(wt.agents, sessionName: sessionName)
                let dashTabs = session.entriesForWorktree(worktreeId).map { TabEntry.sessionEntry($0, sessionName: sessionName) }
                return manifestTabs + dashTabs
            }
            return session.entriesForMaster().map { TabEntry.sessionEntry($0, sessionName: sessionName) }
        }
    }

    private func groupedAgentTabs(_ agents: [AgentModel], sessionName: String) -> [TabEntry] {
        let grouped = Dictionary(grouping: agents) { agent -> String in
            let target = agent.tmuxTarget
            if let dotIndex = target.lastIndex(of: ".") {
                return String(target[target.startIndex..<dotIndex])
            }
            return target
        }
        let sortedKeys = grouped.keys.sorted { k1, k2 in
            let firstId1 = grouped[k1]!.first!.id
            let firstId2 = grouped[k2]!.first!.id
            let i1 = agents.firstIndex(where: { $0.id == firstId1 }) ?? 0
            let i2 = agents.firstIndex(where: { $0.id == firstId2 }) ?? 0
            return i1 < i2
        }
        return sortedKeys.compactMap { key -> TabEntry? in
            guard let group = grouped[key] else { return nil }
            if group.count == 1 {
                return .manifestAgent(group[0], sessionName: sessionName)
            } else {
                return .agentGroup(group, key, sessionName: sessionName)
            }
        }
    }

    private func handleRefresh(_ currentItem: SidebarItem?) {
        guard let item = currentItem else { return }
        let newTabs = computeTabs(for: item)
        let newIds = newTabs.map(\.id)
        if content.currentTabIds() == newIds {
            content.updateTabs(with: newTabs)
        } else {
            content.showTabs(for: newTabs)
        }
    }

    private func handleSelection(_ item: SidebarItem) {
        let newTabs = computeTabs(for: item)
        showTabsIfChanged(newTabs)

        switch item {
        case .agent(let ag):
            content.selectTab(matchingId: ag.id)
        case .terminal(let entry):
            content.selectTab(matchingId: entry.id)
        case .project, .worktree:
            break
        }
    }

    private func showTabsIfChanged(_ newTabs: [TabEntry]) {
        let newIds = newTabs.map(\.id)
        if content.currentTabIds() == newIds { return }
        content.showTabs(for: newTabs)
    }

    private func addAgent(project: ProjectContext, parentWorktreeId: String?) {
        let workingDir = workingDirectory(project: project, worktreeId: parentWorktreeId)
        let entry = project.dashboardSession.addAgent(
            sessionName: project.sessionName,
            parentWorktreeId: parentWorktreeId,
            command: project.agentCommand,
            workingDir: workingDir
        )
        content.addTab(.sessionEntry(entry, sessionName: project.sessionName))
        sidebar.refresh()
    }

    private func addTerminal(project: ProjectContext, parentWorktreeId: String?) {
        let workingDir = workingDirectory(project: project, worktreeId: parentWorktreeId)
        let entry = project.dashboardSession.addTerminal(
            parentWorktreeId: parentWorktreeId,
            workingDir: workingDir
        )
        content.addTab(.sessionEntry(entry, sessionName: project.sessionName))
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

    private func killManifestAgent(project: ProjectContext, agentId: String) {
        let projectRoot = project.projectRoot
        guard !projectRoot.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = PPGService.shared.runPPGCommand("kill --agent \(shellEscape(agentId)) --json", projectRoot: projectRoot)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if result.exitCode != 0 {
                    let alert = NSAlert()
                    alert.messageText = "Failed to Kill Agent"
                    alert.informativeText = result.stderr.isEmpty ? result.stdout : result.stderr
                    alert.alertStyle = .warning
                    alert.runModal()
                }
                self.content.removeTab(byId: agentId)
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
