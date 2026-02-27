import SwiftUI

struct AgentRow: View {
    let agent: AgentEntry
    var onKill: (() -> Void)?
    var onRestart: (() -> Void)?

    @State private var confirmingKill = false

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
                if let date = agent.startDate {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                actionButtons
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog("Kill Agent", isPresented: $confirmingKill) {
            if let onKill {
                Button("Kill", role: .destructive) {
                    onKill()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Kill agent \"\(agent.name)\"? This cannot be undone.")
        }
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
            if agent.status.isActive, onKill != nil {
                Button {
                    confirmingKill = true
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }

            if (agent.status == .failed || agent.status == .killed), let onRestart {
                Button {
                    onRestart()
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
