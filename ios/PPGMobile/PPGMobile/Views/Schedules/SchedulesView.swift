import SwiftUI

/// Placeholder view for schedules.
/// The server needs a `/api/schedules` endpoint before this can show real data.
struct SchedulesView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Schedules", systemImage: "calendar")
        } description: {
            Text("Schedule management requires the server `/api/schedules` endpoint, which is not yet available.")
        } actions: {
            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .navigationTitle("Schedules")
    }
}
