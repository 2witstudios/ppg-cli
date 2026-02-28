import SwiftUI

// MARK: - Sidebar Tab

enum SidebarTab: String, CaseIterable, Identifiable {
    case dashboard
    case swarms
    case prompts
    case schedules
    case agentConfig

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard:   "Dashboard"
        case .swarms:      "Swarms"
        case .prompts:     "Prompts"
        case .schedules:   "Schedules"
        case .agentConfig: "Agent Config"
        }
    }

    var icon: String {
        switch self {
        case .dashboard:   "square.grid.2x2"
        case .swarms:      "person.3"
        case .prompts:     "doc.text"
        case .schedules:   "calendar"
        case .agentConfig: "gearshape.2"
        }
    }

    var destination: DetailDestination {
        switch self {
        case .dashboard:   .dashboard
        case .swarms:      .swarms
        case .prompts:     .prompts
        case .schedules:   .schedules
        case .agentConfig: .agentConfig
        }
    }
}

// MARK: - Detail Destination

enum DetailDestination: Hashable {
    case dashboard
    case worktreeDetail(String)
    case worktreePaneGrid(worktreeId: String)
    case agentTerminal(agentId: String, agentName: String)
    case prompts
    case swarms
    case schedules
    case agentConfig
    case settings
}

// MARK: - Navigation Router

@MainActor
@Observable
final class NavigationRouter {
    var selectedTab: SidebarTab = .dashboard
    var selectedWorktreeId: String?
    var selectedAgentId: String?

    var activeDetail: DetailDestination? = .dashboard

    func navigateToTab(_ tab: SidebarTab) {
        selectedTab = tab
        selectedWorktreeId = nil
        selectedAgentId = nil
        activeDetail = tab.destination
    }

    func navigateToWorktree(_ id: String) {
        selectedTab = .dashboard
        selectedWorktreeId = id
        selectedAgentId = nil
        activeDetail = .worktreeDetail(id)
    }

    func navigateToAgent(agentId: String, agentName: String) {
        selectedAgentId = agentId
        activeDetail = .agentTerminal(agentId: agentId, agentName: agentName)
    }

    func navigateToPaneGrid(worktreeId: String) {
        activeDetail = .worktreePaneGrid(worktreeId: worktreeId)
    }
}
