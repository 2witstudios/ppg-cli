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
    let sessionId: String?
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
    let sessionId: String?

    init(id: String, name: String, agentType: String, status: AgentStatus, tmuxTarget: String, prompt: String, startedAt: String, sessionId: String? = nil) {
        self.id = id
        self.name = name
        self.agentType = agentType
        self.status = status
        self.tmuxTarget = tmuxTarget
        self.prompt = prompt
        self.startedAt = startedAt
        self.sessionId = sessionId
    }

    convenience init(from entry: AgentEntryModel) {
        self.init(
            id: entry.id,
            name: entry.name,
            agentType: entry.agentType,
            status: AgentStatus(rawValue: entry.status) ?? .lost,
            tmuxTarget: entry.tmuxTarget,
            prompt: entry.prompt,
            startedAt: entry.startedAt,
            sessionId: entry.sessionId
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

// MARK: - ProjectState

extension Notification.Name {
    static let projectDidChange = Notification.Name("PPGProjectDidChange")
}

nonisolated class ProjectState: @unchecked Sendable {
    nonisolated(unsafe) static let shared = ProjectState()

    private(set) var projectRoot: String = ""
    private(set) var manifestPath: String = ""
    private(set) var sessionName: String = ""
    private(set) var projectName: String = ""
    private(set) var agentCommand: String = "claude --dangerously-skip-permissions"

    var isConfigured: Bool {
        !projectRoot.isEmpty && projectRoot != "/"
    }

    func loadFromLaunchConfig(_ config: LaunchConfig) {
        projectRoot = config.projectRoot
        manifestPath = config.manifestPath
        sessionName = config.sessionName
        projectName = config.projectName
        agentCommand = config.agentCommand
    }

    func switchProject(root: String) {
        projectRoot = root
        projectName = URL(fileURLWithPath: root).lastPathComponent

        let pgDir = (root as NSString).appendingPathComponent(".pg")
        manifestPath = (pgDir as NSString).appendingPathComponent("manifest.json")

        // Try to read sessionName from manifest
        if let data = FileManager.default.contents(atPath: manifestPath),
           let manifest = try? JSONDecoder().decode(ManifestModel.self, from: data) {
            sessionName = manifest.sessionName
        } else {
            sessionName = "ppg"
        }

        RecentProjects.shared.add(root)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .projectDidChange, object: nil)
        }
    }
}

// MARK: - RecentProjects

nonisolated class RecentProjects: @unchecked Sendable {
    nonisolated(unsafe) static let shared = RecentProjects()

    private let key = "PPGRecentProjects"
    private let maxCount = 10

    var projects: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func add(_ path: String) {
        var list = projects
        list.removeAll { $0 == path }
        list.insert(path, at: 0)
        if list.count > maxCount {
            list = Array(list.prefix(maxCount))
        }
        UserDefaults.standard.set(list, forKey: key)
    }

    func isValidProject(_ path: String) -> Bool {
        let manifestPath = (path as NSString)
            .appendingPathComponent(".pg")
            .appending("/manifest.json")
        return FileManager.default.fileExists(atPath: manifestPath)
    }
}
