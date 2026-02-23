import AppKit

class ProjectPickerViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onProjectSelected: ((String) -> Void)?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let openButton = NSButton(title: "Open Other...", target: nil, action: nil)
    private var recentProjects: [String] = []

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        recentProjects = RecentProjects.shared.projects.filter { RecentProjects.shared.isValidProject($0) }

        // Title
        let titleLabel = NSTextField(labelWithString: "Select a Project")
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "Choose a PPG-initialized project to open")
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleLabel)

        // Table for recent projects
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("project"))
        column.title = "Recent Projects"
        column.width = 500
        tableView.addTableColumn(column)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 50
        tableView.doubleAction = #selector(tableDoubleClicked(_:))
        tableView.target = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // Buttons
        openButton.target = self
        openButton.action = #selector(openOtherClicked(_:))
        openButton.bezelStyle = .glass
        openButton.translatesAutoresizingMaskIntoConstraints = false

        let openSelectedButton = NSButton(title: "Open", target: self, action: #selector(openSelectedClicked(_:)))
        openSelectedButton.bezelStyle = .glass
        openSelectedButton.keyEquivalent = "\r"
        openSelectedButton.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = NSStackView(views: [openButton, NSView(), openSelectedButton])
        buttonStack.orientation = .horizontal
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 40),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            scrollView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            scrollView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -16),

            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            buttonStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            buttonStack.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    // MARK: - Actions

    @objc private func openOtherClicked(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a project directory with .pg/manifest.json"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path

        guard RecentProjects.shared.isValidProject(path) else {
            let alert = NSAlert()
            alert.messageText = "Not a PPG Project"
            alert.informativeText = "The selected directory does not contain .pg/manifest.json. Run 'ppg init' in that directory first."
            alert.alertStyle = .warning
            alert.runModal()
            return
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

        let cell = NSTableCellView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        let nameField = NSTextField(labelWithString: name)
        nameField.font = .boldSystemFont(ofSize: 13)

        let pathField = NSTextField(labelWithString: path)
        pathField.font = .systemFont(ofSize: 11)
        pathField.textColor = .secondaryLabelColor

        stack.addArrangedSubview(nameField)
        stack.addArrangedSubview(pathField)

        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
