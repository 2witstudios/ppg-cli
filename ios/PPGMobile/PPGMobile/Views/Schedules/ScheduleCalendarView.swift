import SwiftUI

/// Calendar grid for schedule visualization.
/// Placeholder — will render day/week/month when `/api/schedules` is available.
struct ScheduleCalendarView: View {
    enum ViewMode: String, CaseIterable {
        case day = "Day"
        case week = "Week"
        case month = "Month"
    }

    @State private var viewMode: ViewMode = .week

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Spacer()

            ContentUnavailableView(
                "No Schedule Data",
                systemImage: "calendar.badge.clock",
                description: Text("Connect to a server with the schedules API to view calendar data.")
            )

            Spacer()
        }
    }
}
