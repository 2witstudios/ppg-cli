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

        sidebar.onRenameTerminal = { [weak self] id, newLabel in
            guard let self = self else { return }
            DashboardSession.shared.rename(id: id, newLabel: newLabel)
            self.content.updateTabLabel(id: id, newLabel: newLabel)
            self.sidebar.refresh()
        }

        sidebar.onDeleteTerminal = { [weak self] id in
            guard let self = self else { return }
            self.content.removeTab(byId: id)
            DashboardSession.shared.remove(id: id)
            self.sidebar.refresh()
        }
    }

    private func handleSelection(_ item: SidebarItem) {
        switch item {
        case .master:
            let dashEntries = DashboardSession.shared.entriesForMaster().map { TabEntry.sessionEntry($0) }
            showTabsIfChanged(dashEntries)

        case .worktree(let wt):
            let manifestTabs = wt.agents.map { TabEntry.manifestAgent($0) }
            let dashTabs = DashboardSession.shared.entriesForWorktree(wt.id).map { TabEntry.sessionEntry($0) }
            showTabsIfChanged(manifestTabs + dashTabs)

        case .agent(let ag):
            // Find parent worktree to show all its tabs, then select this agent
            if let wt = sidebar.worktrees.first(where: { $0.agents.contains(where: { $0.id == ag.id }) }) {
                let manifestTabs = wt.agents.map { TabEntry.manifestAgent($0) }
                let dashTabs = DashboardSession.shared.entriesForWorktree(wt.id).map { TabEntry.sessionEntry($0) }
                showTabsIfChanged(manifestTabs + dashTabs)
                content.selectTab(matchingId: ag.id)
            } else {
                content.showTabs(for: [.manifestAgent(ag)])
            }

        case .terminal(let entry):
            // Show parent's tabs then select this terminal
            if let worktreeId = entry.parentWorktreeId,
               let wt = sidebar.worktrees.first(where: { $0.id == worktreeId }) {
                let manifestTabs = wt.agents.map { TabEntry.manifestAgent($0) }
                let dashTabs = DashboardSession.shared.entriesForWorktree(worktreeId).map { TabEntry.sessionEntry($0) }
                showTabsIfChanged(manifestTabs + dashTabs)
            } else {
                let dashEntries = DashboardSession.shared.entriesForMaster().map { TabEntry.sessionEntry($0) }
                showTabsIfChanged(dashEntries)
            }
            content.selectTab(matchingId: entry.id)
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
            command: LaunchConfig.shared.agentCommand,
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

    private func workingDirectory(for worktreeId: String?) -> String {
        if let wtId = worktreeId,
           let wt = sidebar.worktrees.first(where: { $0.id == wtId }) {
            return wt.path
        }
        let root = LaunchConfig.shared.projectRoot
        return root.isEmpty ? FileManager.default.currentDirectoryPath : root
    }
}
