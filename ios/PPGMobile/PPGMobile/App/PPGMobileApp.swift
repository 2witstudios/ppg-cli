import SwiftUI

@main
struct PPGMobileApp: App {
    @State private var appState = AppState()
    @State private var router = NavigationRouter()

    var body: some Scene {
        WindowGroup {
            RootNavigationView()
                .environment(appState)
                .environment(router)
                .task {
                    await appState.autoConnect()
                }
        }
    }
}
