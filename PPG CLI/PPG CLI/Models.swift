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
    nonisolated(unsafe) static var shared = LaunchConfig(manifestPath: "", sessionName: "", projectName: "", projectRoot: "")

    let manifestPath: String
    let sessionName: String
    let projectName: String
    let projectRoot: String

    static func parse(_ args: [String]) -> LaunchConfig {
        var manifestPath = ""
        var sessionName = ""
        var projectRoot = ""

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

        return LaunchConfig(manifestPath: manifestPath, sessionName: sessionName, projectName: projectName, projectRoot: projectRoot)
    }
}

// MARK: - ProjectState

extension Notification.Name {
    static let projectDidChange = Notification.Name("PoguProjectDidChange")
}

nonisolated class ProjectState: @unchecked Sendable {
    static let shared = ProjectState()

    private(set) var projectRoot: String = ""
    private(set) var manifestPath: String = ""
    private(set) var sessionName: String = ""
    private(set) var projectName: String = ""

    var isConfigured: Bool {
        !projectRoot.isEmpty && projectRoot != "/"
    }

    func loadFromLaunchConfig(_ config: LaunchConfig) {
        projectRoot = config.projectRoot
        manifestPath = config.manifestPath
        sessionName = config.sessionName
        projectName = config.projectName
    }

    func switchProject(root: String) {
        projectRoot = root
        projectName = URL(fileURLWithPath: root).lastPathComponent

        let poguDir = (root as NSString).appendingPathComponent(".pogu")
        manifestPath = (poguDir as NSString).appendingPathComponent("manifest.json")

        // Try to read sessionName from manifest
        if let data = FileManager.default.contents(atPath: manifestPath),
           let manifest = try? JSONDecoder().decode(ManifestModel.self, from: data) {
            sessionName = manifest.sessionName
        } else {
            sessionName = "pogu"
        }

        RecentProjects.shared.add(root)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .projectDidChange, object: nil)
        }
    }
}

// MARK: - RecentProjects

nonisolated class RecentProjects: @unchecked Sendable {
    static let shared = RecentProjects()

    private let key = "PoguRecentProjects"
    private let lastOpenedKey = "PoguLastOpenedProject"
    private let maxCount = 10

    var projects: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    var lastOpened: String? {
        UserDefaults.standard.string(forKey: lastOpenedKey)
    }

    func add(_ path: String) {
        var list = projects
        list.removeAll { $0 == path }
        list.insert(path, at: 0)
        if list.count > maxCount {
            list = Array(list.prefix(maxCount))
        }
        UserDefaults.standard.set(list, forKey: key)
        UserDefaults.standard.set(path, forKey: lastOpenedKey)
    }

    func isValidProject(_ path: String) -> Bool {
        let manifestPath = (path as NSString)
            .appendingPathComponent(".pogu")
            .appending("/manifest.json")
        return FileManager.default.fileExists(atPath: manifestPath)
    }
}

// MARK: - ProjectContext

class ProjectContext {
    let projectRoot: String
    let projectName: String
    let manifestPath: String
    var sessionName: String
    let dashboardSession: DashboardSession

    /// Each variant defines its own default command in AgentVariant.
    func agentCommand(for variant: AgentVariant) -> String {
        variant.defaultCommand
    }

    init(projectRoot: String) {
        self.projectRoot = projectRoot
        self.projectName = URL(fileURLWithPath: projectRoot).lastPathComponent

        let poguDir = (projectRoot as NSString).appendingPathComponent(".pogu")
        self.manifestPath = (poguDir as NSString).appendingPathComponent("manifest.json")

        // Read sessionName from manifest
        if let data = FileManager.default.contents(atPath: self.manifestPath),
           let manifest = try? JSONDecoder().decode(ManifestModel.self, from: data) {
            self.sessionName = manifest.sessionName
        } else {
            self.sessionName = "pogu"
        }

        self.dashboardSession = DashboardSession(projectRoot: projectRoot)
    }
}

// MARK: - OpenProjects

class OpenProjects {
    static let shared = OpenProjects()

    private let key = "PoguOpenProjects"
    private(set) var projects: [ProjectContext] = []

    init() {
        loadFromDisk()
    }

    @discardableResult
    func add(root: String) -> ProjectContext {
        // If already open, return existing
        if let existing = projects.first(where: { $0.projectRoot == root }) {
            return existing
        }
        let ctx = ProjectContext(projectRoot: root)
        projects.append(ctx)
        RecentProjects.shared.add(root)
        save()
        return ctx
    }

    func remove(root: String) {
        projects.removeAll { $0.projectRoot == root }
        save()
    }

    func project(at index: Int) -> ProjectContext? {
        guard index >= 0, index < projects.count else { return nil }
        return projects[index]
    }

    func indexOf(root: String) -> Int? {
        projects.firstIndex(where: { $0.projectRoot == root })
    }

    func save() {
        let roots = projects.map(\.projectRoot)
        UserDefaults.standard.set(roots, forKey: key)
    }

    func loadFromDisk() {
        let roots = UserDefaults.standard.stringArray(forKey: key) ?? []
        projects = roots
            .filter { RecentProjects.shared.isValidProject($0) }
            .map { ProjectContext(projectRoot: $0) }
    }
}
