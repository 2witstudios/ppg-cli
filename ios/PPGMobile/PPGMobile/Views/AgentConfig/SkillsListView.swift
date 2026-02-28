import SwiftUI

/// Read-only skills browser.
/// Shows skills from the server when `/api/skills` endpoint is available.
struct SkillsListView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Skills", systemImage: "sparkles")
        } description: {
            Text("Skills browser requires the server `/api/skills` endpoint, which is not yet available.")
        } actions: {
            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
