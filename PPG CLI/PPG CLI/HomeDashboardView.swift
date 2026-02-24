import AppKit

// MARK: - Data Models

struct AgentStatusCounts {
    var running = 0
    var completed = 0
    var failed = 0
    var killed = 0
    var other = 0

    var total: Int { running + completed + failed + killed + other }
}

struct CommitInfo {
    let hash: String
    let message: String
    let author: String
    let relativeTime: String
    let timestamp: Int  // unix timestamp for sorting
}

struct ProjectDashboardData {
    let projectRoot: String
    let projectName: String
    let branch: String
    let worktreeCount: Int
    let agentCounts: AgentStatusCounts
    let heatmap: CommitHeatmapView.HeatmapData
    let recentCommits: [CommitInfo]
}

// MARK: - HomeDashboardView

class HomeDashboardView: NSView {

    private let scrollView = NSScrollView()
    private let outerStack = NSStackView()

    // Aggregate stats bar
    private let projectCountLabel = NSTextField(labelWithString: "")
    private let agentStatsLabel = NSTextField(labelWithString: "")

    // Per-project card views (reused on refresh)
    private var projectCards: [String: ProjectCardView] = [:]

    private var lastHeatmapFetch: Date?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = terminalBackground.cgColor

        // Outer stack (vertical)
        outerStack.orientation = .vertical
        outerStack.spacing = 16
        outerStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        outerStack.setHuggingPriority(.defaultLow, for: .horizontal)

        // Scroll view
        scrollView.documentView = outerStack
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = terminalBackground
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            outerStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
        ])

        // Stats bar
        let statsBar = NSStackView()
        statsBar.orientation = .horizontal
        statsBar.spacing = 16
        statsBar.alignment = .centerY

        projectCountLabel.font = .systemFont(ofSize: 13, weight: .medium)
        projectCountLabel.textColor = terminalForeground
        agentStatsLabel.font = .systemFont(ofSize: 13)
        agentStatsLabel.textColor = .secondaryLabelColor

        statsBar.addArrangedSubview(projectCountLabel)
        statsBar.addArrangedSubview(agentStatsLabel)
        statsBar.addArrangedSubview(NSView())  // spacer
        outerStack.addArrangedSubview(statsBar)
    }

    // MARK: - Public API

    /// Called from ContentViewController. Kicks off a background fetch and updates UI.
    func configure(projects: [ProjectContext], worktreesByProject: [String: [WorktreeModel]]) {
        let shouldFetchHeatmap: Bool
        if let last = lastHeatmapFetch {
            shouldFetchHeatmap = Date().timeIntervalSince(last) > 60
        } else {
            shouldFetchHeatmap = true
        }
        if shouldFetchHeatmap { lastHeatmapFetch = Date() }

        // Compute agent counts immediately (cheap)
        var totalAgentCounts = AgentStatusCounts()
        var totalWorktrees = 0

        // Snapshot data we need for background work
        var projectSnapshots: [(root: String, name: String, manifestPath: String, worktreeCount: Int, agentCounts: AgentStatusCounts)] = []

        for ctx in projects {
            let worktrees = worktreesByProject[ctx.projectRoot] ?? []
            totalWorktrees += worktrees.count

            var counts = AgentStatusCounts()
            for wt in worktrees {
                for agent in wt.agents {
                    switch agent.status {
                    case .running, .spawning: counts.running += 1
                    case .completed: counts.completed += 1
                    case .failed: counts.failed += 1
                    case .killed: counts.killed += 1
                    case .lost, .waiting: counts.other += 1
                    }
                }
            }
            totalAgentCounts.running += counts.running
            totalAgentCounts.completed += counts.completed
            totalAgentCounts.failed += counts.failed
            totalAgentCounts.killed += counts.killed
            totalAgentCounts.other += counts.other

            projectSnapshots.append((
                root: ctx.projectRoot,
                name: ctx.projectName,
                manifestPath: ctx.manifestPath,
                worktreeCount: worktrees.count,
                agentCounts: counts
            ))
        }

        // Update aggregate stats bar immediately
        projectCountLabel.stringValue = "\(projects.count) project\(projects.count == 1 ? "" : "s"), \(totalWorktrees) worktree\(totalWorktrees == 1 ? "" : "s")"
        updateAgentStatsLabel(totalAgentCounts)

        // Background: fetch git data per project
        let fetchHeatmap = shouldFetchHeatmap
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var results: [ProjectDashboardData] = []
            for snap in projectSnapshots {
                let branch = Self.fetchBranch(projectRoot: snap.root)
                let heatmap: CommitHeatmapView.HeatmapData
                if fetchHeatmap {
                    heatmap = Self.fetchHeatmapData(projectRoot: snap.root)
                } else {
                    heatmap = CommitHeatmapView.HeatmapData(commitsByDate: [:])
                }
                let commits = Self.fetchRecentCommits(projectRoot: snap.root)

                results.append(ProjectDashboardData(
                    projectRoot: snap.root,
                    projectName: snap.name,
                    branch: branch,
                    worktreeCount: snap.worktreeCount,
                    agentCounts: snap.agentCounts,
                    heatmap: heatmap,
                    recentCommits: commits
                ))
            }

            DispatchQueue.main.async {
                self?.updateCards(results, skipHeatmap: !fetchHeatmap)
            }
        }
    }

    // MARK: - Update UI

    private func updateAgentStatsLabel(_ counts: AgentStatusCounts) {
        var parts: [String] = []
        if counts.running > 0 { parts.append("\(counts.running) running") }
        if counts.completed > 0 { parts.append("\(counts.completed) completed") }
        if counts.failed > 0 { parts.append("\(counts.failed) failed") }
        if counts.killed > 0 { parts.append("\(counts.killed) killed") }
        agentStatsLabel.stringValue = parts.isEmpty ? "No agents" : parts.joined(separator: " · ")
    }

    private func updateCards(_ data: [ProjectDashboardData], skipHeatmap: Bool) {
        // Remove cards for projects no longer present
        let activeRoots = Set(data.map(\.projectRoot))
        for (root, card) in projectCards where !activeRoots.contains(root) {
            outerStack.removeArrangedSubview(card)
            card.removeFromSuperview()
            projectCards.removeValue(forKey: root)
        }

        for projectData in data {
            if let card = projectCards[projectData.projectRoot] {
                card.update(data: projectData, skipHeatmap: skipHeatmap)
            } else {
                let card = ProjectCardView()
                card.update(data: projectData, skipHeatmap: false)
                outerStack.addArrangedSubview(card)
                card.translatesAutoresizingMaskIntoConstraints = false
                card.leadingAnchor.constraint(equalTo: outerStack.leadingAnchor, constant: 20).isActive = true
                card.trailingAnchor.constraint(equalTo: outerStack.trailingAnchor, constant: -20).isActive = true
                projectCards[projectData.projectRoot] = card
            }
        }
    }

    // MARK: - Static Git Fetch Methods

    static func fetchBranch(projectRoot: String) -> String {
        let result = PPGService.shared.runGitCommand(["rev-parse", "--abbrev-ref", "HEAD"], cwd: projectRoot)
        let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? "main" : branch
    }

    static func fetchHeatmapData(projectRoot: String) -> CommitHeatmapView.HeatmapData {
        let result = PPGService.shared.runGitCommand([
            "log", "--format=%ad", "--date=format:%Y-%m-%d", "--since=91 days ago", "--all"
        ], cwd: projectRoot)

        var commitsByDate: [String: Int] = [:]
        for line in result.stdout.components(separatedBy: "\n") {
            let date = line.trimmingCharacters(in: .whitespaces)
            guard !date.isEmpty else { continue }
            commitsByDate[date, default: 0] += 1
        }
        return CommitHeatmapView.HeatmapData(commitsByDate: commitsByDate)
    }

    static func fetchRecentCommits(projectRoot: String) -> [CommitInfo] {
        // Use null-byte delimiter for safety
        let result = PPGService.shared.runGitCommand([
            "log", "-10", "--format=%h%x00%s%x00%an%x00%ar%x00%at"
        ], cwd: projectRoot)

        var commits: [CommitInfo] = []
        for line in result.stdout.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "\0")
            guard parts.count >= 5 else { continue }
            commits.append(CommitInfo(
                hash: parts[0],
                message: parts[1],
                author: parts[2],
                relativeTime: parts[3],
                timestamp: Int(parts[4]) ?? 0
            ))
        }
        return commits
    }
}

// MARK: - ProjectCardView

private class ProjectCardView: NSView {

    private let headerView = NSView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let branchTag = NSTextField(labelWithString: "")
    private let wtCountLabel = NSTextField(labelWithString: "")
    private let agentDotsStack = NSStackView()
    private let heatmapView = CommitHeatmapView()
    private let commitsStack = NSStackView()
    private let emptyCommitsLabel = NSTextField(labelWithString: "No recent commits")
    private var isSetUp = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        guard !isSetUp else { return }
        isSetUp = true

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = WorktreeDetailView.cardBackground.cgColor

        // Header
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = WorktreeDetailView.cardHeaderBackground.cgColor
        headerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerView)

        iconView.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Project")
        iconView.contentTintColor = .controlAccentColor
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .boldSystemFont(ofSize: 14)
        nameLabel.textColor = terminalForeground
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        branchTag.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        branchTag.textColor = .secondaryLabelColor
        branchTag.wantsLayer = true
        branchTag.layer?.cornerRadius = 3
        branchTag.layer?.backgroundColor = NSColor(white: 0.2, alpha: 1).cgColor
        branchTag.translatesAutoresizingMaskIntoConstraints = false

        wtCountLabel.font = .systemFont(ofSize: 11)
        wtCountLabel.textColor = .tertiaryLabelColor
        wtCountLabel.translatesAutoresizingMaskIntoConstraints = false

        agentDotsStack.orientation = .horizontal
        agentDotsStack.spacing = 4
        agentDotsStack.translatesAutoresizingMaskIntoConstraints = false

        headerView.addSubview(iconView)
        headerView.addSubview(nameLabel)
        headerView.addSubview(branchTag)
        headerView.addSubview(wtCountLabel)
        headerView.addSubview(agentDotsStack)

        // Body: heatmap + commits
        let bodyStack = NSStackView()
        bodyStack.orientation = .vertical
        bodyStack.spacing = 12
        bodyStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        bodyStack.alignment = .leading
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bodyStack)

        heatmapView.translatesAutoresizingMaskIntoConstraints = false
        bodyStack.addArrangedSubview(heatmapView)

        // Commits section
        let commitsHeader = NSTextField(labelWithString: "Recent Commits")
        commitsHeader.font = .systemFont(ofSize: 11, weight: .medium)
        commitsHeader.textColor = .secondaryLabelColor
        commitsHeader.translatesAutoresizingMaskIntoConstraints = false
        bodyStack.addArrangedSubview(commitsHeader)

        commitsStack.orientation = .vertical
        commitsStack.spacing = 2
        commitsStack.alignment = .leading
        commitsStack.translatesAutoresizingMaskIntoConstraints = false
        bodyStack.addArrangedSubview(commitsStack)

        emptyCommitsLabel.font = .systemFont(ofSize: 12)
        emptyCommitsLabel.textColor = .tertiaryLabelColor
        emptyCommitsLabel.isHidden = true
        emptyCommitsLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyStack.addArrangedSubview(emptyCommitsLabel)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 40),

            iconView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            branchTag.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            branchTag.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            wtCountLabel.leadingAnchor.constraint(equalTo: branchTag.trailingAnchor, constant: 8),
            wtCountLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            agentDotsStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            agentDotsStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            bodyStack.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            bodyStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            bodyStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            bodyStack.bottomAnchor.constraint(equalTo: bottomAnchor),

            commitsStack.leadingAnchor.constraint(equalTo: bodyStack.leadingAnchor, constant: 12),
            commitsStack.trailingAnchor.constraint(equalTo: bodyStack.trailingAnchor, constant: -12),
        ])
    }

    func update(data: ProjectDashboardData, skipHeatmap: Bool) {
        nameLabel.stringValue = data.projectName
        branchTag.stringValue = " \(data.branch) "
        wtCountLabel.stringValue = "\(data.worktreeCount) worktree\(data.worktreeCount == 1 ? "" : "s")"

        // Agent status dots
        for v in agentDotsStack.arrangedSubviews { agentDotsStack.removeArrangedSubview(v); v.removeFromSuperview() }
        addDots(count: data.agentCounts.running, color: statusColor(for: .running))
        addDots(count: data.agentCounts.completed, color: statusColor(for: .completed))
        addDots(count: data.agentCounts.failed, color: statusColor(for: .failed))
        addDots(count: data.agentCounts.killed, color: statusColor(for: .killed))

        // Heatmap
        if !skipHeatmap {
            heatmapView.configure(heatmapData: data.heatmap)
        }

        // Recent commits
        for v in commitsStack.arrangedSubviews { commitsStack.removeArrangedSubview(v); v.removeFromSuperview() }

        if data.recentCommits.isEmpty {
            emptyCommitsLabel.isHidden = false
        } else {
            emptyCommitsLabel.isHidden = true
            for commit in data.recentCommits {
                let row = makeCommitRow(commit)
                commitsStack.addArrangedSubview(row)
            }
        }
    }

    private func addDots(count: Int, color: NSColor) {
        for _ in 0..<count {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.backgroundColor = color.cgColor
            dot.layer?.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
            agentDotsStack.addArrangedSubview(dot)
        }
    }

    private func makeCommitRow(_ commit: CommitInfo) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .firstBaseline

        let monoFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        let hashLabel = NSTextField(labelWithString: commit.hash)
        hashLabel.font = monoFont
        hashLabel.textColor = .controlAccentColor
        hashLabel.setContentHuggingPriority(.required, for: .horizontal)

        let msgLabel = NSTextField(labelWithString: commit.message)
        msgLabel.font = .systemFont(ofSize: 11)
        msgLabel.textColor = terminalForeground
        msgLabel.lineBreakMode = .byTruncatingTail
        msgLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let authorLabel = NSTextField(labelWithString: commit.author)
        authorLabel.font = .systemFont(ofSize: 10)
        authorLabel.textColor = .tertiaryLabelColor
        authorLabel.setContentHuggingPriority(.required, for: .horizontal)

        let timeLabel = NSTextField(labelWithString: commit.relativeTime)
        timeLabel.font = .systemFont(ofSize: 10)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        row.addArrangedSubview(hashLabel)
        row.addArrangedSubview(msgLabel)
        row.addArrangedSubview(authorLabel)
        row.addArrangedSubview(timeLabel)

        return row
    }
}
