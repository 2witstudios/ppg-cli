import SwiftUI

struct WorktreeCard: View {
    let worktree: WorktreeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(worktree.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(worktree.branch)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                statusBadge
            }

            HStack(spacing: 8) {
                Label("\(worktree.agents.count)", systemImage: "person.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !activeAgents.isEmpty {
                    Label("\(activeAgents.count) active", systemImage: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }

                if !failedAgents.isEmpty {
                    Label("\(failedAgents.count) failed", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                Spacer()

                if let date = worktree.createdDate {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
        .glassCard(padding: 0)
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: worktree.status.icon)
                .font(.caption2)
            Text(worktree.status.label)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(worktree.status.color.opacity(0.15))
        .foregroundStyle(worktree.status.color)
        .clipShape(Capsule())
    }

    // MARK: - Helpers

    private var activeAgents: [AgentEntry] {
        worktree.sortedAgents.filter { $0.status.isActive }
    }

    private var failedAgents: [AgentEntry] {
        worktree.sortedAgents.filter { $0.status == .failed }
    }
}
