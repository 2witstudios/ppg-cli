import SwiftUI

/// Wrapper that looks up a worktree by ID and passes its agents to PaneGridView.
struct WorktreePaneGridView: View {
    let worktreeId: String

    @Environment(AppState.self) private var appState
    @Environment(NavigationRouter.self) private var router

    private var worktree: WorktreeEntry? {
        appState.manifest?.worktrees[worktreeId]
    }

    var body: some View {
        Group {
            if let worktree {
                let agents = worktree.sortedAgents
                if agents.isEmpty {
                    ContentUnavailableView(
                        "No Agents",
                        systemImage: "rectangle.split.2x2",
                        description: Text("This worktree has no agents to display.")
                    )
                } else {
                    PaneGridView(agents: agents)
                }
            } else {
                ContentUnavailableView(
                    "Worktree Not Found",
                    systemImage: "questionmark.folder",
                    description: Text("This worktree may have been removed.")
                )
            }
        }
        .navigationTitle(worktree?.name ?? "Terminal Grid")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let worktree {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        Image(systemName: worktree.status.sfSymbol)
                            .font(.caption2)
                        Text(worktree.status.label)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(worktree.status.color)
                }
            }
        }
    }
}
