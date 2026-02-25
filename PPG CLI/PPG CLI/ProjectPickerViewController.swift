import AppKit

class ProjectPickerViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onProjectSelected: ((String) -> Void)?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var recentProjects: [String] = []
    private var hoveredRow: Int = -1
    private weak var listContainer: NSView?

    override func loadView() {
        let root = ThemeAwareView()
        root.onAppearanceChanged = { [weak self] in
            guard let self = self else { return }
            self.view.layer?.backgroundColor = Theme.chromeBackground.resolvedCGColor(for: self.view.effectiveAppearance)
            self.listContainer?.layer?.borderColor = NSColor.separatorColor.resolvedCGColor(for: self.view.effectiveAppearance)
        }
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.backgroundColor = Theme.chromeBackground.resolvedCGColor(for: view.effectiveAppearance)

        recentProjects = RecentProjects.shared.projects.filter { RecentProjects.shared.isValidProject($0) }

        // Container card — centered, fixed-width
        let card = NSView()
        card.wantsLayer = true
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        // Icon
        let iconView = NSImageView()
        if let folderImage = NSImage(systemSymbolName: "folder.fill.badge.gearshape", accessibilityDescription: "Projects") {
            let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .light)
            iconView.image = folderImage.withSymbolConfiguration(config)
            iconView.contentTintColor = .controlAccentColor
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(iconView)

        // Title
        let titleLabel = NSTextField(labelWithString: "Open a Project")
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)

        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: "Select a PPG-initialized project to get started")
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = .tertiaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(subtitleLabel)

        // Table
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.selectionHighlightStyle = .regular
        tableView.style = .plain
        tableView.rowHeight = 56

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("project"))
        column.width = 460
        tableView.addTableColumn(column)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(tableDoubleClicked(_:))
        tableView.target = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Rounded border for the list area
        let listContainer = NSView()
        listContainer.wantsLayer = true
        listContainer.layer?.cornerRadius = 10
        listContainer.layer?.borderWidth = 1
        listContainer.layer?.borderColor = NSColor.separatorColor.resolvedCGColor(for: view.effectiveAppearance)
        listContainer.layer?.masksToBounds = true
        listContainer.translatesAutoresizingMaskIntoConstraints = false
        self.listContainer = listContainer
        card.addSubview(listContainer)
        listContainer.addSubview(scrollView)

        // Section header
        let sectionLabel = NSTextField(labelWithString: "RECENT PROJECTS")
        sectionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        sectionLabel.textColor = .tertiaryLabelColor
        sectionLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(sectionLabel)

        // Empty state
        let emptyLabel = NSTextField(labelWithString: "No recent projects found.\nUse \"Open Other...\" to select a project directory.")
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.maximumNumberOfLines = 0
        emptyLabel.lineBreakMode = .byWordWrapping
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = !recentProjects.isEmpty
        card.addSubview(emptyLabel)

        // Buttons
        let openOtherButton = NSButton(title: "Open Other...", target: self, action: #selector(openOtherClicked(_:)))
        openOtherButton.bezelStyle = .rounded
        openOtherButton.controlSize = .large
        openOtherButton.translatesAutoresizingMaskIntoConstraints = false

        let openButton = NSButton(title: "Open", target: self, action: #selector(openSelectedClicked(_:)))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .large
        openButton.keyEquivalent = "\r"
        openButton.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = NSStackView(views: [openOtherButton, NSView(), openButton])
        buttonStack.orientation = .horizontal
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(buttonStack)

        let cardWidth: CGFloat = 520
        let listHeight: CGFloat = recentProjects.isEmpty ? 100 : min(CGFloat(recentProjects.count) * 60 + 8, 300)

        NSLayoutConstraint.activate([
            // Center the card
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            card.widthAnchor.constraint(equalToConstant: cardWidth),

            // Icon
            iconView.topAnchor.constraint(equalTo: card.topAnchor),
            iconView.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            // Title
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            titleLabel.widthAnchor.constraint(equalTo: card.widthAnchor),

            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            subtitleLabel.widthAnchor.constraint(equalTo: card.widthAnchor),

            // Section header
            sectionLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 28),
            sectionLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 4),

            // List container
            listContainer.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 8),
            listContainer.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            listContainer.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            listContainer.heightAnchor.constraint(equalToConstant: listHeight),

            // Scroll view fills list container
            scrollView.topAnchor.constraint(equalTo: listContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),

            // Empty state
            emptyLabel.centerXAnchor.constraint(equalTo: listContainer.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: listContainer.centerYAnchor),
            emptyLabel.widthAnchor.constraint(equalTo: listContainer.widthAnchor, constant: -32),

            // Buttons
            buttonStack.topAnchor.constraint(equalTo: listContainer.bottomAnchor, constant: 20),
            buttonStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            buttonStack.heightAnchor.constraint(equalToConstant: 32),
        ])

        // Pre-select first row if available
        if !recentProjects.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    // MARK: - Actions

    @objc private func openOtherClicked(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a project directory"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path

        if !RecentProjects.shared.isValidProject(path) {
            guard PPGService.shared.isGitRepo(path) else {
                let alert = NSAlert()
                alert.messageText = "Not a Git Repository"
                alert.informativeText = "ppg requires a git repository. Initialize one with 'git init' first."
                alert.alertStyle = .warning
                alert.runModal()
                return
            }

            let alert = NSAlert()
            alert.messageText = "Initialize PPG?"
            alert.informativeText = "This directory isn't set up for ppg yet. Initialize it now?"
            alert.addButton(withTitle: "Initialize")
            alert.addButton(withTitle: "Cancel")

            guard alert.runModal() == .alertFirstButtonReturn else { return }

            guard PPGService.shared.initProject(at: path) else {
                let errAlert = NSAlert()
                errAlert.messageText = "Initialization Failed"
                errAlert.informativeText = "ppg init failed. Make sure ppg CLI and tmux are installed."
                errAlert.alertStyle = .critical
                errAlert.runModal()
                return
            }
        }

        onProjectSelected?(path)
    }

    @objc private func openSelectedClicked(_ sender: Any) {
        openSelectedProject()
    }

    @objc private func tableDoubleClicked(_ sender: Any) {
        openSelectedProject()
    }

    private func openSelectedProject() {
        let row = tableView.selectedRow
        guard row >= 0, row < recentProjects.count else { return }
        onProjectSelected?(recentProjects[row])
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        recentProjects.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let path = recentProjects[row]
        let name = URL(fileURLWithPath: path).lastPathComponent
        let abbreviated = abbreviatePath(path)

        let cell = NSTableCellView()
        cell.wantsLayer = true

        // Folder icon
        let iconView = NSImageView()
        if let folderImage = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Folder") {
            let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
            iconView.image = folderImage.withSymbolConfiguration(config)
            iconView.contentTintColor = .controlAccentColor
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let nameField = NSTextField(labelWithString: name)
        nameField.font = .systemFont(ofSize: 13, weight: .medium)
        nameField.textColor = .labelColor
        nameField.lineBreakMode = .byTruncatingTail

        let pathField = NSTextField(labelWithString: abbreviated)
        pathField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pathField.textColor = .tertiaryLabelColor
        pathField.lineBreakMode = .byTruncatingMiddle

        let textStack = NSStackView(views: [nameField, pathField])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let rowStack = NSStackView(views: [iconView, textStack])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(rowStack)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            rowStack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            rowStack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            rowStack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
