import SwiftUI

/// List of swarm definitions from the server API.
struct SwarmsListView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedSwarm: String?

    var body: some View {
        List(selection: $selectedSwarm) {
            if appState.swarms.isEmpty {
                ContentUnavailableView(
                    "No Swarms",
                    systemImage: "person.3",
                    description: Text("No swarm definitions found on the server.")
                )
            } else {
                ForEach(appState.swarms, id: \.self) { swarm in
                    NavigationLink(value: swarm) {
                        HStack {
                            Image(systemName: "person.3")
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading) {
                                Text(swarm)
                                    .font(.body)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Swarms")
        .navigationDestination(for: String.self) { swarm in
            SwarmDetailView(swarmName: swarm)
        }
        .task {
            await appState.fetchSwarms()
        }
    }
}
