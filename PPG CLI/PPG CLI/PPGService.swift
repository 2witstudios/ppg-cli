import Foundation

nonisolated class PPGService: @unchecked Sendable {
    static let shared = PPGService()

    var manifestPath: String { LaunchConfig.shared.manifestPath }

    func readManifest() -> ManifestModel? {
        guard !manifestPath.isEmpty else { return nil }
        guard let data = FileManager.default.contents(atPath: manifestPath) else { return nil }
        return try? JSONDecoder().decode(ManifestModel.self, from: data)
    }

    func refreshStatus() -> [WorktreeModel] {
        guard let manifest = readManifest() else { return [] }

        return manifest.worktrees.values
            .sorted { $0.createdAt < $1.createdAt }
            .map { entry in
                let agents = entry.agents.values
                    .sorted { $0.startedAt < $1.startedAt }
                    .map { AgentModel(from: $0) }
                return WorktreeModel(
                    id: entry.id,
                    name: entry.name,
                    path: entry.path,
                    branch: entry.branch,
                    status: entry.status,
                    tmuxWindow: entry.tmuxWindow,
                    agents: agents
                )
            }
    }
}
