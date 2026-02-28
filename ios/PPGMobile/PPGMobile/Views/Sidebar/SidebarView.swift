import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(NavigationRouter.self) private var router

    @Binding var isShowing: Bool
    @State private var showingSpawnSheet = false

    private let bgColor = Color(white: 0.12)

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(appState.manifest?.sessionName ?? "PPG")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                connectionBadge
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().overlay(Color(white: 0.22))

            // Scrollable content
            ScrollView {
                VStack(spacing: 0) {
                    // MARK: - Navigation Tabs
                    ForEach(SidebarTab.allCases) { tab in
                        sidebarButton(label: tab.label, icon: tab.icon) {
                            router.activeDetail = tab.destination
                            dismissSidebar()
                        }
                    }

                    Divider().overlay(Color(white: 0.22)).padding(.vertical, 4)

                    // MARK: - Projects / Worktree / Agent Tree
                    if let projects = appState.projects, !projects.isEmpty {
                        ForEach(projects) { project in
                            projectSection(project)
                        }
                    } else if let manifest = appState.manifest {
                        singleProjectSection(manifest)
                    }

                    Divider().overlay(Color(white: 0.22)).padding(.vertical, 4)

                    // MARK: - Spawn Action
                    sidebarButton(label: "Spawn Agent", icon: "plus.circle") {
                        showingSpawnSheet = true
                    }
                }
                .padding(.vertical, 4)
            }

            Divider().overlay(Color(white: 0.22))

            // Footer — Settings gear + Add Project
            HStack {
                Button {
                    router.activeDetail = .settings
                    dismissSidebar()
                } label: {
                    Image(systemName: "gear")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showingSpawnSheet = true
                } label: {
                    Label("Add Project", systemImage: "plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
        }
        .background(bgColor)
        .sheet(isPresented: $showingSpawnSheet) {
            SpawnView()
                .environment(appState)
        }
    }

    // MARK: - Sidebar Button

    private func sidebarButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)
                Text(label)
                    .font(.caption)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dismiss Helper

    private func dismissSidebar() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isShowing = false
        }
    }

    // MARK: - Multi-Project Section

    @ViewBuilder
    private func projectSection(_ project: ProjectInfo) -> some View {
        DisclosureGroup {
            // Master agents
            ForEach(project.manifest.sortedMasterAgents) { agent in
                agentRow(agent)
                    .padding(.leading, 12)
            }

            // Worktrees
            ForEach(project.manifest.sortedWorktrees) { worktree in
                worktreeRow(worktree)
                    .padding(.leading, 12)
            }

            // Untracked tmux windows
            untrackedWindowsSection(project.manifest.untrackedWindows)
                .padding(.leading, 12)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(project.sessionName)
                    .font(.caption)
                    .fontWeight(.bold)

                Spacer()

                Text("\(project.manifest.worktrees.count)")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color(white: 0.2))
                    .clipShape(Capsule())

                projectStatusDots(project.manifest)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Project Status Dots

    @ViewBuilder
    private func projectStatusDots(_ manifest: Manifest) -> some View {
        let agents = manifest.allAgents
        let running = agents.filter { $0.status == .running }.count
        let failed = agents.filter { $0.status == .failed }.count
        let completed = agents.filter { $0.status == .completed }.count

        HStack(spacing: 3) {
            if running > 0 {
                Circle().fill(.green).frame(width: 6, height: 6)
            }
            if failed > 0 {
                Circle().fill(.red).frame(width: 6, height: 6)
            }
            if completed > 0 {
                Circle().fill(.blue).frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Single Project (backwards compat)

    @ViewBuilder
    private func singleProjectSection(_ manifest: Manifest) -> some View {
        // Master agents
        ForEach(manifest.sortedMasterAgents) { agent in
            agentRow(agent)
        }

        // Worktrees
        ForEach(manifest.sortedWorktrees) { worktree in
            worktreeRow(worktree)
        }

        // Untracked tmux windows
        untrackedWindowsSection(manifest.untrackedWindows)
    }

    // MARK: - Untracked Windows

    @ViewBuilder
    private func untrackedWindowsSection(_ windows: [UntrackedWindow]) -> some View {
        let liveWindows = windows.filter { !$0.isDead }
        if !liveWindows.isEmpty {
            Divider().overlay(Color(white: 0.22)).padding(.vertical, 2)

            ForEach(liveWindows) { window in
                Button {
                    router.activeDetail = .agentTerminal(
                        agentId: window.tmuxTarget,
                        agentName: window.windowName
                    )
                    dismissSidebar()
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(.orange).frame(width: 6, height: 6)
                        Text(window.windowName)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Worktree Row

    @ViewBuilder
    private func worktreeRow(_ worktree: WorktreeEntry) -> some View {
        DisclosureGroup {
            ForEach(worktree.sortedAgents) { agent in
                agentRow(agent)
                    .padding(.leading, 12)
            }
        } label: {
            Button {
                router.activeDetail = .worktreeDetail(worktree.id)
                dismissSidebar()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: worktree.status.sfSymbol)
                        .foregroundStyle(worktree.status.color)
                        .font(.caption2)

                    Text(worktree.name)
                        .font(.caption)
                        .fontWeight(.medium)

                    Spacer()

                    Text("\(worktree.agents.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    // MARK: - Agent Row

    private func agentRow(_ agent: AgentEntry) -> some View {
        Button {
            router.activeDetail = .agentTerminal(
                agentId: agent.id,
                agentName: agent.name
            )
            dismissSidebar()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(agent.status.color)
                    .frame(width: 6, height: 6)

                Text("\(agent.name) — \(agent.agentType)")
                    .font(.caption)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Connection Badge

    @ViewBuilder
    private var connectionBadge: some View {
        switch appState.connectionStatus {
        case .connected:
            Image(systemName: "circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .connecting:
            ProgressView()
                .controlSize(.mini)
        case .error(_):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .disconnected:
            Image(systemName: "circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
