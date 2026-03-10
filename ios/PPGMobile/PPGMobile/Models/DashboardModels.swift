import SwiftUI

// MARK: - Connection State (UI-only, distinct from WebSocketConnectionState)

enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case error(String)
}

// MARK: - Diff Stats

struct DiffStats {
    let filesChanged: Int
    let insertions: Int
    let deletions: Int
}

struct DiffResponse: Codable {
    let diff: String?
    let stats: DiffStatsResponse?
}

struct DiffStatsResponse: Codable {
    let filesChanged: Int
    let insertions: Int
    let deletions: Int
}

// MARK: - API Response Types

struct SpawnResponse: Codable {
    let success: Bool
    let worktreeId: String
}

struct LogsResponse: Codable {
    let output: String
}

struct Config: Codable {
    let sessionName: String?
}

struct TemplatesResponse: Codable {
    let templates: [String]
}

struct PromptsResponse: Codable {
    let prompts: [String]
}

struct SwarmsResponse: Codable {
    let swarms: [String]
}

struct ErrorResponse: Codable {
    let error: String
}

// MARK: - AgentStatus UI Extensions

extension AgentStatus {
    var icon: String { sfSymbol }

    var isActive: Bool {
        self == .spawning || self == .running
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .killed, .lost: true
        default: false
        }
    }
}

// MARK: - WorktreeStatus UI Extensions

extension WorktreeStatus {
    var icon: String { sfSymbol }

    var isTerminal: Bool {
        self == .merged || self == .cleaned
    }
}

// MARK: - AgentEntry UI Extensions

extension AgentEntry {
    var startDate: Date? {
        ISO8601DateFormatter().date(from: startedAt)
    }
}

// MARK: - WorktreeEntry UI Extensions

extension WorktreeEntry {
    var createdDate: Date? {
        ISO8601DateFormatter().date(from: createdAt)
    }

    var mergedDate: Date? {
        mergedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
    }
}
