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
        addSplitViewItem(contentItem)

        sidebar.onItemSelected = { [weak self] item in
            self?.handleSelection(item)
        }

        sidebar.onAddAgent = { [weak self] worktreeId in
            self?.addAgent(parentWorktreeId: worktreeId)
        }

        sidebar.onAddTerminal = { [weak self] worktreeId in
            self?.addTerminal(parentWorktreeId: worktreeId)
        }

        sidebar.onAddWorktree = { [weak self] in
            self?.createWorktree()
        }

        sidebar.onDataRefreshed = { [weak self] currentItem in
            self?.handleRefresh(currentItem)
        }

        sidebar.onRenameTerminal = { [weak self] id, newLabel in
            guard let self = self else { return }
            DashboardSession.shared.rename(id: id, newLabel: newLabel)
            self.content.updateTabLabel(id: id, newLabel: newLabel)
            self.sidebar.refresh()
        }

        sidebar.onDeleteTerminal = { [weak self] id in
            guard let self = self else { return }
            // Kill the tmux window if this is a tmux-backed entry
            if let entry = DashboardSession.shared.entry(byId: id),
               let tmuxTarget = entry.tmuxTarget {
                DashboardSession.shared.killTmuxWindow(target: tmuxTarget)
            }
            self.content.removeTab(byId: id)
            DashboardSession.shared.remove(id: id)
            self.sidebar.refresh()
        }

        sidebar.onRenameAgent = { [weak self] agentId, newName in
            guard let self = self else { return }
            self.renameManifestAgent(agentId: agentId, newName: newName)
        }

        sidebar.onKillAgent = { [weak self] agentId in
            guard let self = self else { return }
            self.killManifestAgent(agentId: agentId)
        }
    }

    /// Compute the tabs for a given sidebar item.
    private func computeTabs(for item: SidebarItem) -> [TabEntry] {
        switch item {
        case .master:
            return DashboardSession.shared.entriesForMaster().map { TabEntry.sessionEntry($0) }

        case .worktree(let wt):
            let manifestTabs = groupedAgentTabs(wt.agents)
            let dashTabs = DashboardSession.shared.entriesForWorktree(wt.id).map { TabEntry.sessionEntry($0) }
            return manifestTabs + dashTabs

        case .agent(let ag):
            if let wt = sidebar.worktrees.first(where: { $0.agents.contains(where: { $0.id == ag.id }) }) {
                let manifestTabs = groupedAgentTabs(wt.agents)
                let dashTabs = DashboardSession.shared.entriesForWorktree(wt.id).map { TabEntry.sessionEntry($0) }
                return manifestTabs + dashTabs
            }
            return [.manifestAgent(ag)]

        case .terminal(let entry):
            if let worktreeId = entry.parentWorktreeId,
               let wt = sidebar.worktrees.first(where: { $0.id == worktreeId }) {
                let manifestTabs = groupedAgentTabs(wt.agents)
                let dashTabs = DashboardSession.shared.entriesForWorktree(worktreeId).map { TabEntry.sessionEntry($0) }
                return manifestTabs + dashTabs
            }
            return DashboardSession.shared.entriesForMaster().map { TabEntry.sessionEntry($0) }
        }
    }

    /// Group agents by their tmux window target. Agents sharing the same window
    /// (split panes) produce a single `.agentGroup` tab; unique windows produce
    /// individual `.manifestAgent` tabs.
    private func groupedAgentTabs(_ agents: [AgentModel]) -> [TabEntry] {
        // Extract the window portion from the tmux target.
        // Window targets: "ppg:3" → "ppg:3"; pane IDs: "%42" → group by pane parent unknown,
        // so we use the full target string as-is for grouping.
        let grouped = Dictionary(grouping: agents) { agent -> String in
            let target = agent.tmuxTarget
            // If target contains "." it's "session:window.pane" — strip the pane suffix
            if let dotIndex = target.lastIndex(of: ".") {
                return String(target[target.startIndex..<dotIndex])
            }
            // Pane ID like "%42" — can't determine parent window, use as-is
            return target
        }
        // Sort groups by first agent's order in the original array for stability
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
                return .manifestAgent(group[0])
            } else {
                return .agentGroup(group, key)
            }
        }
    }

    /// Called after every sidebar data refresh. Updates tab metadata without tearing down terminals.
    private func handleRefresh(_ currentItem: SidebarItem?) {
        guard let item = currentItem else { return }
        let newTabs = computeTabs(for: item)
        let newIds = newTabs.map(\.id)
        if content.currentTabIds() == newIds {
            // Same tabs — just update metadata in-place (status labels, etc.)
            content.updateTabs(with: newTabs)
        } else {
            // Tab set changed — full rebuild
            content.showTabs(for: newTabs)
        }
    }

    private func handleSelection(_ item: SidebarItem) {
        let newTabs = computeTabs(for: item)
        showTabsIfChanged(newTabs)

        // For specific items, select the matching tab
        switch item {
        case .agent(let ag):
            content.selectTab(matchingId: ag.id)
        case .terminal(let entry):
            content.selectTab(matchingId: entry.id)
        case .master, .worktree:
            break
        }
    }

    /// Only rebuild tabs if the set of tab IDs has changed, preserving current tab selection.
    private func showTabsIfChanged(_ newTabs: [TabEntry]) {
        let newIds = newTabs.map(\.id)
        if content.currentTabIds() == newIds { return }
        content.showTabs(for: newTabs)
    }

    private func addAgent(parentWorktreeId: String?) {
        let workingDir = workingDirectory(for: parentWorktreeId)
        let entry = DashboardSession.shared.addAgent(
            parentWorktreeId: parentWorktreeId,
            command: ProjectState.shared.agentCommand,
            workingDir: workingDir
        )
        content.addTab(.sessionEntry(entry))
        sidebar.refresh()
    }

    private func addTerminal(parentWorktreeId: String?) {
        let workingDir = workingDirectory(for: parentWorktreeId)
        let entry = DashboardSession.shared.addTerminal(
            parentWorktreeId: parentWorktreeId,
            workingDir: workingDir
        )
        content.addTab(.sessionEntry(entry))
        sidebar.refresh()
    }

    private func createWorktree() {
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

        let projectRoot = ProjectState.shared.projectRoot
        guard !projectRoot.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let escapedName = name.replacingOccurrences(of: "'", with: "'\\''")
            let result = PPGService.shared.runPPGCommand("worktree create --name '\(escapedName)' --json", projectRoot: projectRoot)

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

    private func renameManifestAgent(agentId: String, newName: String) {
        let projectRoot = ProjectState.shared.projectRoot
        guard !projectRoot.isEmpty else { return }

        // Update the manifest JSON directly
        let manifestPath = ProjectState.shared.manifestPath
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

    private func killManifestAgent(agentId: String) {
        let projectRoot = ProjectState.shared.projectRoot
        guard !projectRoot.isEmpty else { return }

        // Use ppg kill to properly terminate the agent
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = PPGService.shared.runPPGCommand("kill --agent \(agentId) --json", projectRoot: projectRoot)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if result.exitCode != 0 {
                    let alert = NSAlert()
                    alert.messageText = "Failed to Kill Agent"
                    alert.informativeText = result.stderr.isEmpty ? result.stdout : result.stderr
                    alert.alertStyle = .warning
                    alert.runModal()
                }
                // Remove the tab and refresh regardless (status will update from manifest)
                self.content.removeTab(byId: agentId)
                self.sidebar.refresh()
            }
        }
    }

    private func workingDirectory(for worktreeId: String?) -> String {
        if let wtId = worktreeId,
           let wt = sidebar.worktrees.first(where: { $0.id == wtId }) {
            return wt.path
        }
        let root = ProjectState.shared.projectRoot
        if !root.isEmpty, root != "/" { return root }
        if let manifest = PPGService.shared.readManifest(), !manifest.projectRoot.isEmpty {
            return manifest.projectRoot
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }
}
