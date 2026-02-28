import SwiftUI

/// iPad multi-pane terminal grid layout.
/// Lays out agent terminals in a grid: 1=full, 2=split, 3-4=2x2, 5-6=2x3.
struct PaneGridView: View {
    let agents: [AgentEntry]

    @Environment(AppState.self) private var appState

    var body: some View {
        GeometryReader { geometry in
            let layout = gridLayout(for: agents.count, in: geometry.size)

            ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                if index < layout.frames.count {
                    SwiftTermView(agentId: agent.id)
                        .frame(
                            width: layout.frames[index].width,
                            height: layout.frames[index].height
                        )
                        .position(
                            x: layout.frames[index].midX,
                            y: layout.frames[index].midY
                        )
                        .overlay(alignment: .top) {
                            PaneHeaderBar(agent: agent)
                        }
                }
            }
        }
    }

    private struct GridLayout {
        let frames: [CGRect]
    }

    private func gridLayout(for count: Int, in size: CGSize) -> GridLayout {
        let gap: CGFloat = 2
        var frames: [CGRect] = []

        switch count {
        case 0:
            break
        case 1:
            frames = [CGRect(origin: .zero, size: size)]
        case 2:
            let w = (size.width - gap) / 2
            frames = [
                CGRect(x: 0, y: 0, width: w, height: size.height),
                CGRect(x: w + gap, y: 0, width: w, height: size.height),
            ]
        case 3, 4:
            let cols = 2
            let rows = 2
            let w = (size.width - gap) / CGFloat(cols)
            let h = (size.height - gap) / CGFloat(rows)
            for i in 0..<min(count, 4) {
                let col = i % cols
                let row = i / cols
                frames.append(CGRect(
                    x: CGFloat(col) * (w + gap),
                    y: CGFloat(row) * (h + gap),
                    width: w,
                    height: h
                ))
            }
        default:
            let cols = 3
            let rows = 2
            let w = (size.width - gap * 2) / CGFloat(cols)
            let h = (size.height - gap) / CGFloat(rows)
            for i in 0..<min(count, 6) {
                let col = i % cols
                let row = i / cols
                frames.append(CGRect(
                    x: CGFloat(col) * (w + gap),
                    y: CGFloat(row) * (h + gap),
                    width: w,
                    height: h
                ))
            }
        }

        return GridLayout(frames: frames)
    }
}

// MARK: - Pane Header Bar

private struct PaneHeaderBar: View {
    let agent: AgentEntry

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(agent.status.color)
                .frame(width: 6, height: 6)

            Text(agent.name)
                .font(.caption2)
                .fontWeight(.medium)
                .lineLimit(1)

            Spacer()

            Text(agent.status.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial)
    }
}
