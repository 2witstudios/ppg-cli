import SwiftUI

/// Agent configuration view with segmented tabs: CLAUDE.md, Skills, Agents.
struct AgentConfigView: View {
    @State private var selectedTab: ConfigTab = .claudeMd

    private enum ConfigTab: String, CaseIterable {
        case claudeMd = "CLAUDE.md"
        case skills = "Skills"
        case agents = "Agents"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Config", selection: $selectedTab) {
                ForEach(ConfigTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case .claudeMd:
                ClaudeMdEditorView()
            case .skills:
                SkillsListView()
            case .agents:
                agentsPlaceholder
            }
        }
        .navigationTitle("Agent Config")
    }

    private var agentsPlaceholder: some View {
        ContentUnavailableView(
            "Agent Definitions",
            systemImage: "person.crop.circle.badge.plus",
            description: Text("Agent type definitions from config.yaml. Coming soon.")
        )
    }
}
