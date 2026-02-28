import SwiftUI

/// Read-only detail view for a swarm definition.
struct SwarmDetailView: View {
    let swarmName: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Read Only", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Section {
                    LabeledContent("Name") {
                        Text(swarmName)
                            .font(.body.monospaced())
                    }
                }

                Text("Swarm configuration is managed on the server. Use the macOS app or edit files directly in `.ppg/swarms/`.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(swarmName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
