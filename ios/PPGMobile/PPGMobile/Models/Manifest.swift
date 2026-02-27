import SwiftUI

// MARK: - Agent Status

/// Lifecycle status for an agent process.
///
/// Matches the ppg agent lifecycle:
///   spawning → running → completed | failed | killed | lost
///
/// Custom decoding also accepts the current TypeScript status values:
///   `"idle"` → `.running`, `"exited"` → `.completed`, `"gone"` → `.lost`
enum AgentStatus: String, Codable, CaseIterable {
    case spawning
    case running
    case completed
    case failed
    case killed
    case lost

    /// Maps legacy/TS status strings to lifecycle values.
    private static let aliases: [String: AgentStatus] = [
        "idle": .running,
        "exited": .completed,
        "gone": .lost,
    ]

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let direct = AgentStatus(rawValue: raw) {
            self = direct
        } else if let mapped = Self.aliases[raw] {
            self = mapped
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Unknown AgentStatus: \(raw)")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var label: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .spawning: .orange
        case .running:  .green
        case .completed: .blue
        case .failed:   .red
        case .killed:   .gray
        case .lost:     .secondary
        }
    }

    var sfSymbol: String {
        switch self {
        case .spawning: "arrow.triangle.2.circlepath"
        case .running:  "play.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .failed:   "xmark.circle.fill"
        case .killed:   "stop.circle.fill"
        case .lost:     "questionmark.circle"
        }
    }
}

// MARK: - Worktree Status

/// Lifecycle status for a git worktree.
///
/// Matches the ppg worktree lifecycle:
///   active → merging → merged → cleaned
///                    → failed
enum WorktreeStatus: String, Codable, CaseIterable {
    case active
    case merging
    case merged
    case failed
    case cleaned

    var label: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .active:  .green
        case .merging: .yellow
        case .merged:  .blue
        case .failed:  .red
        case .cleaned: .gray
        }
    }

    var sfSymbol: String {
        switch self {
        case .active:  "arrow.branch"
        case .merging: "arrow.triangle.merge"
        case .merged:  "checkmark.circle"
        case .failed:  "xmark.circle"
        case .cleaned: "trash.circle"
        }
    }
}

// MARK: - Agent Entry

/// A single agent (CLI process) running in a tmux pane.
///
/// JSON keys use camelCase matching the server schema (e.g. `agentType`, `startedAt`).
struct AgentEntry: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let agentType: String
    var status: AgentStatus
    let tmuxTarget: String
    let prompt: String
    let startedAt: String
    var exitCode: Int?
    var sessionId: String?

    // MARK: Hashable (identity-based)

    static func == (lhs: AgentEntry, rhs: AgentEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Worktree Entry

/// An isolated git checkout on branch `ppg/<name>`.
struct WorktreeEntry: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let branch: String
    let baseBranch: String
    var status: WorktreeStatus
    let tmuxWindow: String
    var prUrl: String?
    var agents: [String: AgentEntry]
    let createdAt: String
    var mergedAt: String?

    // MARK: Hashable (identity-based)

    static func == (lhs: WorktreeEntry, rhs: WorktreeEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Manifest

/// Top-level runtime state persisted in `.ppg/manifest.json`.
struct Manifest: Codable {
    let version: Int
    let projectRoot: String
    let sessionName: String
    var worktrees: [String: WorktreeEntry]
    let createdAt: String
    var updatedAt: String
}

// MARK: - Convenience

extension Manifest {
    /// All agents across all worktrees, flattened.
    var allAgents: [AgentEntry] {
        worktrees.values.flatMap { $0.agents.values }
    }

    /// Worktrees sorted by creation date (newest first).
    var sortedWorktrees: [WorktreeEntry] {
        worktrees.values.sorted { $0.createdAt > $1.createdAt }
    }
}

extension WorktreeEntry {
    /// Agents sorted by start date (newest first).
    var sortedAgents: [AgentEntry] {
        agents.values.sorted { $0.startedAt > $1.startedAt }
    }
}
