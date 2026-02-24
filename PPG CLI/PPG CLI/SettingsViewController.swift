import AppKit

class SettingsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let actions = BindableAction.allCases
    private var recordingRow: Int? = nil
    private var eventMonitor: Any? = nil

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 440))
        container.appearance = NSAppearance(named: .darkAqua)
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"

        view.wantsLayer = true
        view.layer?.backgroundColor = terminalBackground.cgColor

        // Header label
        let header = NSTextField(labelWithString: "Keyboard Shortcuts")
        header.font = .boldSystemFont(ofSize: 16)
        header.textColor = terminalForeground
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        // Table setup
        let actionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionColumn.title = "Action"
        actionColumn.width = 180
        tableView.addTableColumn(actionColumn)

        let shortcutColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shortcut"))
        shortcutColumn.title = "Shortcut"
        shortcutColumn.width = 120
        tableView.addTableColumn(shortcutColumn)

        let recordColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("record"))
        recordColumn.title = ""
        recordColumn.width = 100
        tableView.addTableColumn(recordColumn)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowSizeStyle = .medium
        tableView.backgroundColor = terminalBackground
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.headerView?.wantsLayer = true

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // Bottom button bar
        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetAllDefaults))
        resetButton.bezelStyle = .rounded
        resetButton.translatesAutoresizingMaskIntoConstraints = false

        let doneButton = NSButton(title: "Done", target: self, action: #selector(dismissSettings))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(resetButton)
        view.addSubview(doneButton)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: resetButton.topAnchor, constant: -12),

            resetButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            resetButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),

            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            doneButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
        ])
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        cancelRecording()
        applyAndRefreshMenu()
    }

    // MARK: - Actions

    @objc private func resetAllDefaults() {
        cancelRecording()
        KeybindingManager.shared.resetAll()
        tableView.reloadData()
        applyAndRefreshMenu()
    }

    @objc private func dismissSettings() {
        cancelRecording()
        applyAndRefreshMenu()
        dismiss(nil)
    }

    @objc private func recordButtonClicked(_ sender: NSButton) {
        let row = sender.tag
        let action = actions[row]

        // Cmd+Q cannot be rebound
        if action == .quit {
            let alert = NSAlert()
            alert.messageText = "Cannot Rebind Quit"
            alert.informativeText = "⌘Q is reserved and cannot be changed."
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        cancelRecording()
        recordingRow = row
        sender.title = "Press key…"

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecordedKey(event)
            return nil  // consume the event
        }
    }

    // MARK: - Key Recording

    private func handleRecordedKey(_ event: NSEvent) {
        guard let row = recordingRow else { return }
        let action = actions[row]

        let key = event.charactersIgnoringModifiers ?? ""
        let mods = event.modifierFlags.intersection([.command, .option, .shift, .control])

        // Must include at least Cmd or Ctrl
        guard mods.contains(.command) || mods.contains(.control) else {
            cancelRecording()
            showAlert("Invalid Shortcut", "Shortcuts must include ⌘ or ⌃.")
            return
        }

        guard !key.isEmpty else {
            cancelRecording()
            return
        }

        // Check for conflict
        if let conflict = KeybindingManager.shared.findConflict(keyEquivalent: key, modifiers: mods, excluding: action) {
            cancelRecording()
            let shortcutStr = KeybindingManager.displayString(keyEquivalent: key, modifiers: mods)
            showAlert("Shortcut Conflict", "\(shortcutStr) is already used by \"\(conflict.displayName)\".")
            return
        }

        KeybindingManager.shared.setBinding(for: action, keyEquivalent: key, modifiers: mods)
        cancelRecording()
        tableView.reloadData()
        applyAndRefreshMenu()
    }

    private func cancelRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        recordingRow = nil
        tableView.reloadData()
    }

    private func applyAndRefreshMenu() {
        guard let menu = NSApp.mainMenu else { return }
        KeybindingManager.shared.applyBindings(to: menu)
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        actions.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let action = actions[row]

        switch tableColumn?.identifier.rawValue {
        case "action":
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: action.displayName)
            label.font = .systemFont(ofSize: 13)
            label.textColor = terminalForeground
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell

        case "shortcut":
            let cell = NSTableCellView()
            let shortcutStr = KeybindingManager.shared.displayString(for: action)
            let label = NSTextField(labelWithString: shortcutStr)
            label.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            label.textColor = KeybindingManager.shared.isCustomized(action) ? .systemYellow : terminalForeground
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell

        case "record":
            let cell = NSTableCellView()
            let button = NSButton()
            button.bezelStyle = .rounded
            button.tag = row
            button.target = self
            button.action = #selector(recordButtonClicked(_:))
            button.translatesAutoresizingMaskIntoConstraints = false

            if action == .quit {
                button.title = "Locked"
                button.isEnabled = false
            } else if recordingRow == row {
                button.title = "Press key…"
            } else {
                button.title = "Record"
            }

            cell.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                button.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            ])
            return cell

        default:
            return nil
        }
    }
}
