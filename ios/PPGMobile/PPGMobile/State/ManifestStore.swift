import Foundation

// MARK: - ManifestStore

/// Caches the ppg manifest and applies incremental WebSocket updates.
///
/// `ManifestStore` owns the manifest data and provides read access to views.
/// It is updated either by a full REST fetch or by individual WebSocket events
/// (agent/worktree status changes) to keep the UI responsive without polling.
@MainActor
@Observable
final class ManifestStore {

    // MARK: - Published State

    /// The cached manifest, or `nil` if not yet loaded.
    private(set) var manifest: Manifest?

    /// Whether a fetch is currently in progress.
    private(set) var isLoading = false

    /// Last error from a fetch or WebSocket update.
    private(set) var error: String?

    /// Timestamp of the last successful refresh.
    private(set) var lastRefreshed: Date?

    // MARK: - Dependencies

    private let client: PPGClient

    // MARK: - Init

    init(client: PPGClient) {
        self.client = client
    }

    // MARK: - Full Refresh

    /// Fetches the full manifest from the REST API and replaces the cache.
    func refresh() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let fetched = try await client.fetchStatus()
            manifest = fetched
            lastRefreshed = Date()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Incremental Updates

    /// Applies a full manifest snapshot received from WebSocket.
    func applyManifest(_ updated: Manifest) {
        manifest = updated
        lastRefreshed = Date()
        error = nil
    }

    /// Updates a single agent's status in the cached manifest.
    func updateAgentStatus(agentId: String, status: AgentStatus) {
        guard var m = manifest else { return }
        for (wtId, var worktree) in m.worktrees {
            if var agent = worktree.agents[agentId] {
                agent.status = status
                worktree.agents[agentId] = agent
                m.worktrees[wtId] = worktree
                manifest = m
                lastRefreshed = Date()
                error = nil
                return
            }
        }
    }

    /// Updates a single worktree's status in the cached manifest.
    func updateWorktreeStatus(worktreeId: String, status: WorktreeStatus) {
        guard var m = manifest,
              var worktree = m.worktrees[worktreeId] else { return }
        worktree.status = status
        m.worktrees[worktreeId] = worktree
        manifest = m
        lastRefreshed = Date()
        error = nil
    }

    // MARK: - Clear

    /// Resets the store to its initial empty state.
    func clear() {
        manifest = nil
        isLoading = false
        error = nil
        lastRefreshed = nil
    }

    // MARK: - Convenience

    /// All worktrees sorted by creation date (newest first).
    var sortedWorktrees: [WorktreeEntry] {
        manifest?.sortedWorktrees ?? []
    }

    /// All agents across all worktrees.
    var allAgents: [AgentEntry] {
        manifest?.allAgents ?? []
    }

    /// Counts of agents by status.
    var agentCounts: [AgentStatus: Int] {
        var counts: [AgentStatus: Int] = [:]
        for agent in allAgents {
            counts[agent.status, default: 0] += 1
        }
        return counts
    }
}
