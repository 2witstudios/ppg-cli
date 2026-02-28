import SwiftUI

/// GitHub-style 7x13 commit heatmap grid.
/// Currently shows placeholder data — will wire to a `/api/commits` endpoint when available.
struct CommitHeatmapView: View {
    // Placeholder: 13 weeks x 7 days
    private let weeks = 13
    private let daysPerWeek = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Activity")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack(spacing: 2) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: 2) {
                        ForEach(0..<daysPerWeek, id: \.self) { day in
                            let level = placeholderLevel(week: week, day: day)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(GlassTheme.heatmapColor(level: level))
                                .frame(width: 12, height: 12)
                        }
                    }
                }
            }

            HStack(spacing: 4) {
                Text("Less")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(GlassTheme.heatmapColor(level: level))
                        .frame(width: 10, height: 10)
                }
                Text("More")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Deterministic placeholder levels seeded by position.
    private func placeholderLevel(week: Int, day: Int) -> Int {
        let hash = (week * 7 + day) * 2654435761
        return abs(hash) % 5
    }
}
