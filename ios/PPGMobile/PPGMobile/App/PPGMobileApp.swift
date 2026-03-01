import SwiftUI

@main
struct PPGMobileApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            TabView {
                DashboardView()
                    .tabItem {
                        Label("Dashboard", systemImage: "square.grid.2x2")
                    }

                SpawnView()
                    .tabItem {
                        Label("Spawn", systemImage: "plus.circle")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }
            .environment(appState)
            .task {
                await appState.autoConnect()
            }
        }
    }
}
