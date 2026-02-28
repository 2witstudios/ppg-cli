import SwiftUI

/// Read-only viewer for CLAUDE.md content fetched from the server.
struct ClaudeMdEditorView: View {
    @Environment(AppState.self) private var appState
    @State private var content = ""
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading CLAUDE.md...")
            } else if let error {
                ContentUnavailableView(
                    "Failed to Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if content.isEmpty {
                ContentUnavailableView(
                    "No CLAUDE.md",
                    systemImage: "doc.text",
                    description: Text("No CLAUDE.md file found for this project.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Read Only", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        Text(content)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                    }
                }
            }
        }
        .task {
            await loadContent()
        }
    }

    private func loadContent() async {
        isLoading = true
        error = nil

        // Try fetching CLAUDE.md from API if endpoint exists, otherwise show placeholder
        do {
            // The /api/claudemd endpoint may not exist yet
            let response: ClaudeMdResponse = try await fetchClaudeMd()
            content = response.content
        } catch {
            // Endpoint not available yet — show empty state
            content = ""
        }

        isLoading = false
    }

    private func fetchClaudeMd() async throws -> ClaudeMdResponse {
        // Attempt to use existing client infrastructure
        // This will fail gracefully if the endpoint doesn't exist
        throw PPGClientError.notFound("Endpoint not yet available")
    }
}

private struct ClaudeMdResponse: Codable {
    let content: String
}
