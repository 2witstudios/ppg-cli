import SwiftUI

struct AgentRow: View {
    let agent: Agent
    var onKill: (() -> Void)?
    var onRestart: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: agent.status.icon)
                    .foregroundStyle(agent.status.color)
                    .font(.body)

                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(agent.agentType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusLabel
            }

            Text(agent.prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Text(agent.startedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if let error = agent.error {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }

                Spacer()

                actionButtons
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Status Label

    private var statusLabel: some View {
        Text(agent.status.label)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(agent.status.color.opacity(0.12))
            .foregroundStyle(agent.status.color)
            .clipShape(Capsule())
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            if agent.status.isActive {
                Button {
                    onKill?()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }

            if agent.status == .failed || agent.status == .killed {
                Button {
                    onRestart?()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

#Preview {
    List {
        AgentRow(
            agent: Agent(id: "ag-1", name: "claude-1", agentType: "claude", status: .running, prompt: "Implement the authentication flow with JWT tokens", startedAt: .now.addingTimeInterval(-300), completedAt: nil, exitCode: nil, error: nil),
            onKill: {},
            onRestart: {}
        )

        AgentRow(
            agent: Agent(id: "ag-2", name: "claude-2", agentType: "claude", status: .completed, prompt: "Write unit tests for the auth module", startedAt: .now.addingTimeInterval(-600), completedAt: .now.addingTimeInterval(-120), exitCode: 0, error: nil),
            onKill: {},
            onRestart: {}
        )

        AgentRow(
            agent: Agent(id: "ag-3", name: "codex-1", agentType: "codex", status: .failed, prompt: "Set up middleware pipeline", startedAt: .now.addingTimeInterval(-500), completedAt: .now.addingTimeInterval(-200), exitCode: 1, error: "Process exited with code 1"),
            onKill: {},
            onRestart: {}
        )

        AgentRow(
            agent: Agent(id: "ag-4", name: "claude-3", agentType: "claude", status: .killed, prompt: "Refactor database layer", startedAt: .now.addingTimeInterval(-900), completedAt: nil, exitCode: nil, error: nil),
            onKill: {},
            onRestart: {}
        )
    }
    .listStyle(.insetGrouped)
}
