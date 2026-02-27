import SwiftUI

struct WorktreeCard: View {
    let worktree: Worktree

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(worktree.name)
                        .font(.headline)

                    Text(worktree.branch)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                statusBadge
            }

            HStack(spacing: 12) {
                Label("\(worktree.agents.count)", systemImage: "person.2")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !activeAgents.isEmpty {
                    Label("\(activeAgents.count) active", systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if !failedAgents.isEmpty {
                    Label("\(failedAgents.count) failed", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()

                Text(worktree.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
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

    private var activeAgents: [Agent] {
        worktree.agents.filter { $0.status.isActive }
    }

    private var failedAgents: [Agent] {
        worktree.agents.filter { $0.status == .failed }
    }
}

#Preview {
    List {
        WorktreeCard(worktree: Worktree(
            id: "wt-abc123",
            name: "auth-feature",
            branch: "ppg/auth-feature",
            path: ".worktrees/wt-abc123",
            status: .running,
            agents: [
                Agent(id: "ag-1", name: "claude-1", agentType: "claude", status: .running, prompt: "Implement auth", startedAt: .now, completedAt: nil, exitCode: nil, error: nil),
                Agent(id: "ag-2", name: "claude-2", agentType: "claude", status: .completed, prompt: "Write tests", startedAt: .now, completedAt: .now, exitCode: 0, error: nil),
            ],
            createdAt: .now.addingTimeInterval(-3600),
            mergedAt: nil
        ))

        WorktreeCard(worktree: Worktree(
            id: "wt-def456",
            name: "fix-bug",
            branch: "ppg/fix-bug",
            path: ".worktrees/wt-def456",
            status: .merged,
            agents: [
                Agent(id: "ag-3", name: "codex-1", agentType: "codex", status: .completed, prompt: "Fix bug", startedAt: .now, completedAt: .now, exitCode: 0, error: nil),
            ],
            createdAt: .now.addingTimeInterval(-86400),
            mergedAt: .now.addingTimeInterval(-3600)
        ))
    }
    .listStyle(.insetGrouped)
}
