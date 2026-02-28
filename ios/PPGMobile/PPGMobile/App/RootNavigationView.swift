import SwiftUI
import UIKit

/// Root view using a ZStack drawer overlay for the sidebar.
/// Content is always full-screen; sidebar slides over from the left edge.
struct RootNavigationView: View {
    @Environment(AppState.self) private var appState
    @Environment(NavigationRouter.self) private var router
    @State private var sidebarVisible = false

    var body: some View {
        ZStack(alignment: .leading) {
            // Full-screen content
            NavigationStack {
                DetailContentView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                // Dismiss keyboard before showing sidebar
                                UIApplication.shared.sendAction(
                                    #selector(UIResponder.resignFirstResponder),
                                    to: nil, from: nil, for: nil
                                )
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    sidebarVisible.toggle()
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal")
                            }
                        }
                    }
            }

            // Dimmed backdrop
            if sidebarVisible {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            sidebarVisible = false
                        }
                    }
                    .zIndex(1)
            }

            // Sidebar drawer
            SidebarView(isShowing: $sidebarVisible)
                .frame(width: 280)
                .frame(maxHeight: .infinity)
                .background(Color(white: 0.12))
                .offset(x: sidebarVisible ? 0 : -280)
                .animation(.easeInOut(duration: 0.25), value: sidebarVisible)
                .zIndex(2)
        }
    }
}
