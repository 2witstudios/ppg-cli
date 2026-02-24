import AppKit
import SwiftTerm

enum TabEntry {
    case manifestAgent(AgentModel, sessionName: String)
    case agentGroup([AgentModel], String, sessionName: String)  // agents sharing a tmux window, tmuxTarget, sessionName
    case sessionEntry(DashboardSession.TerminalEntry, sessionName: String)

    var id: String {
        switch self {
        case .manifestAgent(let agent, _): return agent.id
        case .agentGroup(let agents, _, _): return agents.map(\.id).joined(separator: "+")
        case .sessionEntry(let entry, _): return entry.id
        }
    }

    var label: String {
        switch self {
        case .manifestAgent(let agent, _): return agent.name.isEmpty ? agent.id : agent.name
        case .agentGroup(let agents, _, _): return "\(agents.count) agents (split)"
        case .sessionEntry(let entry, _): return entry.label
        }
    }

    var sessionName: String {
        switch self {
        case .manifestAgent(_, let name): return name
        case .agentGroup(_, _, let name): return name
        case .sessionEntry(_, let name): return name
        }
    }
}

class ContentViewController: NSViewController {
    let placeholderLabel = NSTextField(labelWithString: "Select an item from the sidebar")
    private let containerView = NSView()
    private(set) var currentEntry: TabEntry?
    private var terminalViews: [String: NSView] = [:]
    private var worktreeDetailView: WorktreeDetailView?

    var currentEntryId: String? { currentEntry?.id }
    var isShowingWorktreeDetail: Bool { worktreeDetailView?.superview != nil }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.wantsLayer = true
        view.layer?.backgroundColor = chromeBackground.cgColor

        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = terminalBackground.cgColor
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        placeholderLabel.font = .systemFont(ofSize: 16)
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.alignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            placeholderLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func showEntry(_ entry: TabEntry?) {
        worktreeDetailView?.removeFromSuperview()

        guard let entry = entry else {
            // Show placeholder
            for (_, termView) in terminalViews {
                termView.isHidden = true
            }
            currentEntry = nil
            placeholderLabel.isHidden = false
            containerView.isHidden = true
            return
        }

        // Same entry already showing — no-op
        if let current = currentEntry, current.id == entry.id {
            return
        }

        currentEntry = entry
        placeholderLabel.isHidden = true
        containerView.isHidden = false

        for (_, termView) in terminalViews {
            termView.isHidden = true
        }

        let termView = terminalView(for: entry)
        termView.isHidden = false
    }

    func updateCurrentEntry(_ entry: TabEntry) {
        guard let current = currentEntry, current.id == entry.id else { return }
        currentEntry = entry
        switch entry {
        case .manifestAgent(let agent, _):
            if let pane = terminalViews[agent.id] as? TerminalPane {
                pane.updateStatus(agent.status)
            }
        case .agentGroup(let agents, _, _):
            if let pane = terminalViews[entry.id] as? TerminalPane {
                let status = agents.first?.status ?? .lost
                pane.updateStatus(status)
            }
        case .sessionEntry:
            break
        }
    }

    func removeEntry(byId id: String) {
        if let termView = terminalViews[id] {
            terminateTerminal(termView)
            termView.removeFromSuperview()
            terminalViews.removeValue(forKey: id)
        }
        if currentEntry?.id == id {
            currentEntry = nil
            worktreeDetailView?.removeFromSuperview()
            placeholderLabel.isHidden = false
            containerView.isHidden = true
        }
    }

    func clearStaleViews(validIds: Set<String>) {
        let staleIds = terminalViews.keys.filter { !validIds.contains($0) }
        for id in staleIds {
            if let termView = terminalViews[id] {
                terminateTerminal(termView)
                termView.removeFromSuperview()
                terminalViews.removeValue(forKey: id)
            }
        }
    }

    // MARK: - Worktree Detail

    func showWorktreeDetail(
        worktree: WorktreeModel,
        projectRoot: String,
        onNewAgent: @escaping () -> Void,
        onNewTerminal: @escaping () -> Void,
        onNewWorktree: @escaping () -> Void
    ) {
        // Hide terminal views and clear current entry
        for (_, termView) in terminalViews {
            termView.isHidden = true
        }
        currentEntry = nil
        placeholderLabel.isHidden = true
        containerView.isHidden = true

        // Create or reconfigure the detail view
        if worktreeDetailView == nil {
            worktreeDetailView = WorktreeDetailView()
        }
        guard let detailView = worktreeDetailView else { return }

        detailView.configure(
            worktree: worktree,
            onNewAgent: onNewAgent,
            onNewTerminal: onNewTerminal,
            onNewWorktree: onNewWorktree
        )

        if detailView.superview != view {
            detailView.removeFromSuperview()
            detailView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(detailView)
            NSLayoutConstraint.activate([
                detailView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                detailView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                detailView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                detailView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }

        // Load diff on background queue
        let worktreePath = worktree.path
        DispatchQueue.global(qos: .utility).async {
            let diffData = WorktreeDetailView.fetchDiffData(worktreePath: worktreePath)
            DispatchQueue.main.async { [weak detailView] in
                detailView?.updateDiff(diffData)
            }
        }
    }

    func refreshWorktreeDetail() {
        guard let detailView = worktreeDetailView, detailView.superview != nil else { return }
        let worktreePath = detailView.currentWorktreePath
        guard !worktreePath.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            let diffData = WorktreeDetailView.fetchDiffData(worktreePath: worktreePath)
            DispatchQueue.main.async { [weak detailView] in
                detailView?.updateDiff(diffData)
            }
        }
    }

    // MARK: - Private

    private func terminalView(for tab: TabEntry) -> NSView {
        if let existing = terminalViews[tab.id] {
            return existing
        }

        let sessionName = tab.sessionName
        let termView: NSView
        switch tab {
        case .manifestAgent(let agent, _):
            let pane = TerminalPane(agent: agent, sessionName: sessionName)
            termView = pane

        case .agentGroup(let agents, let tmuxTarget, _):
            let lead = agents[0]
            let groupAgent = AgentModel(
                id: tab.id,
                name: lead.name,
                agentType: lead.agentType,
                status: lead.status,
                tmuxTarget: tmuxTarget,
                prompt: lead.prompt,
                startedAt: lead.startedAt
            )
            let pane = TerminalPane(agent: groupAgent, sessionName: sessionName)
            termView = pane

        case .sessionEntry(let entry, _):
            if let tmuxTarget = entry.tmuxTarget {
                let agentModel = AgentModel(
                    id: entry.id,
                    name: entry.label,
                    agentType: entry.kind == .agent ? "claude" : "terminal",
                    status: .running,
                    tmuxTarget: tmuxTarget,
                    prompt: "",
                    startedAt: "",
                    sessionId: entry.sessionId
                )
                let pane = TerminalPane(agent: agentModel, sessionName: sessionName)
                termView = pane
            } else {
                let localTerm = ScrollableTerminalView(frame: containerView.bounds)
                let cmd = """
                if [ -x /usr/libexec/path_helper ]; then eval $(/usr/libexec/path_helper -s); fi; \
                [ -f ~/.zprofile ] && source ~/.zprofile; \
                [ -f ~/.zshrc ] && source ~/.zshrc; \
                cd \(shellEscape(entry.workingDirectory)) && exec \(entry.command)
                """
                localTerm.startProcess(
                    executable: "/bin/zsh",
                    args: ["-c", cmd],
                    environment: nil,
                    execName: "zsh"
                )
                termView = localTerm
            }
        }

        termView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(termView)
        // TerminalPane handles its own leading inset; other views get 8px gap from the container.
        let leadingPadding: CGFloat = (termView is TerminalPane) ? 0 : 8
        NSLayoutConstraint.activate([
            termView.topAnchor.constraint(equalTo: containerView.topAnchor),
            termView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: leadingPadding),
            termView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            termView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        terminalViews[tab.id] = termView
        return termView
    }

    private func terminateTerminal(_ view: NSView) {
        if let pane = view as? TerminalPane {
            pane.terminate()
        } else if let scrollTerm = view as? ScrollableTerminalView {
            scrollTerm.process?.terminate()
        } else if let localTerm = view as? LocalProcessTerminalView {
            localTerm.process?.terminate()
        }
    }
}

// MARK: - WorktreeDetailView

class WorktreeDetailView: NSView {

    struct DiffData {
        let statusLines: [StatusLine]
        let diffText: String

        struct StatusLine {
            let code: String   // M, A, D, ??, etc.
            let file: String
            let added: String  // from --numstat
            let removed: String
        }
    }

    private(set) var currentWorktreePath = ""

    // Header
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let branchLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let agentButton = NSButton()
    private let terminalButton = NSButton()
    private let worktreeButton = NSButton()
    private let headerStack = NSStackView()

    // Diff area
    private let scrollView = NSScrollView()
    private let textView = NSTextView()

    var onNewAgent: (() -> Void)?
    var onNewTerminal: (() -> Void)?
    var onNewWorktree: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    func configure(
        worktree: WorktreeModel,
        onNewAgent: @escaping () -> Void,
        onNewTerminal: @escaping () -> Void,
        onNewWorktree: @escaping () -> Void
    ) {
        currentWorktreePath = worktree.path
        nameLabel.stringValue = worktree.name
        branchLabel.stringValue = worktree.branch
        shortcutLabel.stringValue = "Press \(KeybindingManager.shared.displayString(for: .newItem)) or:"
        self.onNewAgent = onNewAgent
        self.onNewTerminal = onNewTerminal
        self.onNewWorktree = onNewWorktree
    }

    func updateDiff(_ data: DiffData) {
        let attributed = NSMutableAttributedString()
        let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: monoFont,
            .foregroundColor: terminalForeground,
        ]

        if data.statusLines.isEmpty {
            let emptyAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            attributed.append(NSAttributedString(string: "No unstaged changes", attributes: emptyAttrs))
            textView.textStorage?.setAttributedString(attributed)
            return
        }

        // Section header
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: terminalForeground,
        ]
        attributed.append(NSAttributedString(
            string: "Unstaged Changes (\(data.statusLines.count) file\(data.statusLines.count == 1 ? "" : "s"))\n\n",
            attributes: headerAttrs
        ))

        // File status list
        for line in data.statusLines {
            let codeColor: NSColor
            switch line.code {
            case "M": codeColor = .systemYellow
            case "A": codeColor = .systemGreen
            case "D": codeColor = .systemRed
            default:  codeColor = .systemGray
            }
            attributed.append(NSAttributedString(
                string: " \(line.code.padding(toLength: 3, withPad: " ", startingAt: 0))",
                attributes: [.font: monoFont, .foregroundColor: codeColor]
            ))
            attributed.append(NSAttributedString(
                string: line.file,
                attributes: defaultAttrs
            ))
            // Stats
            var stats = ""
            if !line.added.isEmpty && line.added != "-" { stats += "  +\(line.added)" }
            if !line.removed.isEmpty && line.removed != "-" { stats += "  -\(line.removed)" }
            if !stats.isEmpty {
                let statColor: NSColor = .secondaryLabelColor
                attributed.append(NSAttributedString(
                    string: stats,
                    attributes: [.font: monoFont, .foregroundColor: statColor]
                ))
            }
            attributed.append(NSAttributedString(string: "\n", attributes: defaultAttrs))
        }

        // Diff output
        if !data.diffText.isEmpty {
            attributed.append(NSAttributedString(string: "\n", attributes: defaultAttrs))
            let lines = data.diffText.components(separatedBy: "\n")
            for line in lines {
                let color: NSColor
                let font: NSFont
                if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff --git") {
                    color = .secondaryLabelColor
                    font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
                } else if line.hasPrefix("@@") {
                    color = .systemCyan
                    font = monoFont
                } else if line.hasPrefix("+") {
                    color = .systemGreen
                    font = monoFont
                } else if line.hasPrefix("-") {
                    color = .systemRed
                    font = monoFont
                } else {
                    color = terminalForeground
                    font = monoFont
                }
                attributed.append(NSAttributedString(
                    string: line + "\n",
                    attributes: [.font: font, .foregroundColor: color]
                ))
            }
        }

        textView.textStorage?.setAttributedString(attributed)
    }

    // MARK: - Static Helpers

    static func fetchDiffData(worktreePath: String) -> DiffData {
        let service = PPGService.shared

        // git status --porcelain
        let statusResult = service.runGitCommand(["status", "--porcelain"], cwd: worktreePath)
        // git diff --numstat
        let numstatResult = service.runGitCommand(["diff", "--numstat"], cwd: worktreePath)
        // git diff
        let diffResult = service.runGitCommand(["diff"], cwd: worktreePath)

        // Parse numstat into a lookup: filename -> (added, removed)
        var numstatMap: [String: (String, String)] = [:]
        for line in numstatResult.stdout.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.split(separator: "\t", maxSplits: 2)
            if parts.count >= 3 {
                numstatMap[String(parts[2])] = (String(parts[0]), String(parts[1]))
            }
        }

        // Parse status --porcelain
        var statusLines: [DiffData.StatusLine] = []
        for line in statusResult.stdout.components(separatedBy: "\n") where !line.isEmpty {
            guard line.count >= 3 else { continue }
            // Porcelain format: XY filename
            let index = line.index(line.startIndex, offsetBy: 3)
            let file = String(line[index...])
            // Use the working-tree status (Y column), fall back to index status (X column)
            let x = String(line[line.startIndex...line.startIndex])
            let y = String(line[line.index(line.startIndex, offsetBy: 1)...line.index(line.startIndex, offsetBy: 1)])
            let code = (y == " " || y == "?") ? (x == "?" ? "??" : x) : y
            let stats = numstatMap[file] ?? ("", "")
            statusLines.append(DiffData.StatusLine(code: code, file: file, added: stats.0, removed: stats.1))
        }

        return DiffData(statusLines: statusLines, diffText: diffResult.stdout)
    }

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = terminalBackground.cgColor

        // Icon
        iconView.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Worktree")
        iconView.contentTintColor = .controlAccentColor
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // Name
        nameLabel.font = .boldSystemFont(ofSize: 18)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        // Branch
        branchLabel.font = .systemFont(ofSize: 13)
        branchLabel.textColor = .secondaryLabelColor
        branchLabel.lineBreakMode = .byTruncatingTail
        branchLabel.translatesAutoresizingMaskIntoConstraints = false

        // Shortcut hint
        shortcutLabel.font = .systemFont(ofSize: 12)
        shortcutLabel.textColor = .tertiaryLabelColor
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false

        // Action buttons
        configureButton(agentButton, title: "Agent", icon: "cpu")
        configureButton(terminalButton, title: "Terminal", icon: "terminal")
        configureButton(worktreeButton, title: "Worktree", icon: "arrow.triangle.branch")

        agentButton.target = self
        agentButton.action = #selector(agentButtonClicked)
        terminalButton.target = self
        terminalButton.action = #selector(terminalButtonClicked)
        worktreeButton.target = self
        worktreeButton.action = #selector(worktreeButtonClicked)

        // Header layout
        let titleStack = NSStackView(views: [nameLabel, branchLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        let buttonStack = NSStackView(views: [shortcutLabel, agentButton, terminalButton, worktreeButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.alignment = .centerY

        let topRow = NSStackView(views: [iconView, titleStack])
        topRow.orientation = .horizontal
        topRow.spacing = 10
        topRow.alignment = .centerY

        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 8
        headerStack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 12, right: 16)
        headerStack.addArrangedSubview(topRow)
        headerStack.addArrangedSubview(buttonStack)
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerStack)

        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        // Scroll view + text view
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = terminalBackground
        textView.textContainerInset = NSSize(width: 12, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = terminalForeground

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = terminalBackground
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: topAnchor),
            headerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: trailingAnchor),

            separator.topAnchor.constraint(equalTo: headerStack.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    private func configureButton(_ button: NSButton, title: String, icon: String) {
        button.bezelStyle = .accessoryBarAction
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
        button.title = title
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 11)
        button.isBordered = false
        button.contentTintColor = terminalForeground
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func agentButtonClicked() { onNewAgent?() }
    @objc private func terminalButtonClicked() { onNewTerminal?() }
    @objc private func worktreeButtonClicked() { onNewWorktree?() }
}
