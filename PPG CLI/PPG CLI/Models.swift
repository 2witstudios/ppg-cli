import Foundation

// MARK: - Codable Models

nonisolated struct ManifestModel: Codable, Sendable {
    let version: Int
    let projectRoot: String
    let sessionName: String
    let worktrees: [String: WorktreeEntryModel]
    let createdAt: String
    let updatedAt: String
}

nonisolated struct WorktreeEntryModel: Codable, Sendable {
    let id: String
    let name: String
    let path: String
    let branch: String
    let baseBranch: String
    let status: String
    let tmuxWindow: String
    let agents: [String: AgentEntryModel]
    let createdAt: String
    let mergedAt: String?
}

nonisolated struct AgentEntryModel: Codable, Sendable {
    let id: String
    let name: String
    let agentType: String
    let status: String
    let tmuxTarget: String
    let prompt: String
    let resultFile: String
    let startedAt: String
    let completedAt: String?
    let exitCode: Int?
    let error: String?
}

// MARK: - Enums

nonisolated enum AgentStatus: String, CaseIterable, Sendable {
    case spawning
    case running
    case waiting
    case completed
    case failed
    case killed
    case lost
}

// MARK: - View Models (classes for NSOutlineView identity)

nonisolated class WorktreeModel: @unchecked Sendable {
    let id: String
    let name: String
    let path: String
    let branch: String
    let status: String
    let tmuxWindow: String
    var agents: [AgentModel]

    init(id: String, name: String, path: String, branch: String, status: String, tmuxWindow: String, agents: [AgentModel]) {
        self.id = id
        self.name = name
        self.path = path
        self.branch = branch
        self.status = status
        self.tmuxWindow = tmuxWindow
        self.agents = agents
    }
}

nonisolated class AgentModel: @unchecked Sendable {
    let id: String
    let name: String
    let agentType: String
    let status: AgentStatus
    let tmuxTarget: String
    let prompt: String
    let startedAt: String

    init(id: String, name: String, agentType: String, status: AgentStatus, tmuxTarget: String, prompt: String, startedAt: String) {
        self.id = id
        self.name = name
        self.agentType = agentType
        self.status = status
        self.tmuxTarget = tmuxTarget
        self.prompt = prompt
        self.startedAt = startedAt
    }

    convenience init(from entry: AgentEntryModel) {
        self.init(
            id: entry.id,
            name: entry.name,
            agentType: entry.agentType,
            status: AgentStatus(rawValue: entry.status) ?? .lost,
            tmuxTarget: entry.tmuxTarget,
            prompt: entry.prompt,
            startedAt: entry.startedAt
        )
    }
}

// MARK: - LaunchConfig

nonisolated struct LaunchConfig: Sendable {
    nonisolated(unsafe) static var shared = LaunchConfig(manifestPath: "", sessionName: "", projectName: "", projectRoot: "", agentCommand: "claude --dangerously-skip-permissions")

    let manifestPath: String
    let sessionName: String
    let projectName: String
    let projectRoot: String
    let agentCommand: String

    static func parse(_ args: [String]) -> LaunchConfig {
        var manifestPath = ""
        var sessionName = ""
        var projectRoot = ""
        var agentCommand = "claude --dangerously-skip-permissions"

        var i = 0
        while i < args.count {
            if args[i] == "--manifest-path", i + 1 < args.count {
                manifestPath = args[i + 1]
                i += 2
            } else if args[i] == "--session-name", i + 1 < args.count {
                sessionName = args[i + 1]
                i += 2
            } else if args[i] == "--project-root", i + 1 < args.count {
                projectRoot = args[i + 1]
                i += 2
            } else if args[i] == "--agent-command", i + 1 < args.count {
                agentCommand = args[i + 1]
                i += 2
            } else {
                i += 1
            }
        }

        // Derive projectRoot from manifestPath if not explicitly provided
        if projectRoot.isEmpty, !manifestPath.isEmpty {
            let url = URL(fileURLWithPath: manifestPath)
            projectRoot = url.deletingLastPathComponent().deletingLastPathComponent().path
        }

        let projectName: String
        if !projectRoot.isEmpty {
            projectName = URL(fileURLWithPath: projectRoot).lastPathComponent
        } else if !manifestPath.isEmpty {
            let url = URL(fileURLWithPath: manifestPath)
            projectName = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        } else {
            projectName = ""
        }

        return LaunchConfig(manifestPath: manifestPath, sessionName: sessionName, projectName: projectName, projectRoot: projectRoot, agentCommand: agentCommand)
    }
}
