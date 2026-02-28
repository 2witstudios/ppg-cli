import SwiftUI

/// Per-project dashboard card showing session info, agent status, heatmap, and recent worktrees.
struct ProjectCardView: View {
    let project: ProjectInfo

    @Environment(NavigationRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)

                Text(project.sessionName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(project.manifest.worktrees.values.first?.baseBranch ?? "main")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())

                Spacer()

                Text("\(project.manifest.worktrees.count)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())

                agentStatusDots
            }

            // Heatmap
            CommitHeatmapView()
                .frame(height: 100)

            // Recent worktrees (top 3)
            let worktrees = project.manifest.sortedWorktrees.prefix(3)
            if !worktrees.isEmpty {
                VStack(spacing: 4) {
                    ForEach(worktrees) { worktree in
                        Button {
                            router.navigateToWorktree(worktree.id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: worktree.status.sfSymbol)
                                    .foregroundStyle(worktree.status.color)
                                    .font(.caption2)

                                Text(worktree.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(1)

                                Spacer()

                                worktreeAgentDots(worktree)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .glassCard(padding: 8)
    }

    // MARK: - Agent Status Dots

    private var agentStatusDots: some View {
        let agents = project.manifest.allAgents
        let running = agents.filter { $0.status == .running }.count
        let failed = agents.filter { $0.status == .failed }.count
        let completed = agents.filter { $0.status == .completed }.count

        return HStack(spacing: 3) {
            if running > 0 {
                Circle().fill(.green).frame(width: 6, height: 6)
            }
            if failed > 0 {
                Circle().fill(.red).frame(width: 6, height: 6)
            }
            if completed > 0 {
                Circle().fill(.blue).frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Worktree Agent Dots

    private func worktreeAgentDots(_ worktree: WorktreeEntry) -> some View {
        HStack(spacing: 3) {
            ForEach(worktree.sortedAgents.prefix(6)) { agent in
                Circle()
                    .fill(agent.status.color)
                    .frame(width: 6, height: 6)
            }
            if worktree.agents.count > 6 {
                Text("+\(worktree.agents.count - 6)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
