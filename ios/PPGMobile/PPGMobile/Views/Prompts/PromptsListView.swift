import SwiftUI

/// List of prompt and template files from the server API.
/// Read-only — the macOS app reads/writes directly to disk.
struct PromptsListView: View {
    @Environment(AppState.self) private var appState
    @State private var filter: PromptFilter = .all
    @State private var selectedPrompt: String?

    private enum PromptFilter: String, CaseIterable {
        case all = "All"
        case prompts = "Prompts"
        case templates = "Templates"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $filter) {
                ForEach(PromptFilter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            List(selection: $selectedPrompt) {
                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        "No \(filter.rawValue)",
                        systemImage: "doc.text",
                        description: Text("No prompt or template files found on the server.")
                    )
                } else {
                    ForEach(filteredItems, id: \.self) { item in
                        NavigationLink(value: item) {
                            HStack {
                                Image(systemName: item.contains("template") ? "doc.badge.gearshape" : "doc.text")
                                    .foregroundStyle(.secondary)
                                Text(item)
                                    .font(.body)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Prompts")
        .navigationDestination(for: String.self) { prompt in
            PromptEditorView(promptName: prompt)
        }
        .task {
            await appState.fetchPrompts()
            await appState.fetchTemplates()
        }
    }

    private var filteredItems: [String] {
        switch filter {
        case .all: appState.prompts + appState.templates
        case .prompts: appState.prompts
        case .templates: appState.templates
        }
    }
}
