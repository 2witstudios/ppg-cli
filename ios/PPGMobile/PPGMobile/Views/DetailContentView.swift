import SwiftUI

/// Routes the current `NavigationRouter.activeDetail` to the appropriate content view.
struct DetailContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        if let detail = router.activeDetail {
            switch detail {
            case .dashboard:
                HomeDashboardView()

            case .worktreeDetail(let worktreeId):
                WorktreeDetailView(worktreeId: worktreeId)

            case .worktreePaneGrid(let worktreeId):
                WorktreePaneGridView(worktreeId: worktreeId)

            case .agentTerminal(let agentId, let agentName):
                RemoteTerminalView(agentId: agentId, agentName: agentName)

            case .prompts:
                PromptsListView()

            case .swarms:
                SwarmsListView()

            case .schedules:
                SchedulesView()

            case .agentConfig:
                AgentConfigView()

            case .settings:
                SettingsView()
            }
        } else {
            ContentUnavailableView("Select an item", systemImage: "sidebar.left")
        }
    }
}
