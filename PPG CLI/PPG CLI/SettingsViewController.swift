import AppKit

class SettingsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    private let segmentedControl = NSSegmentedControl()
    private let contentContainer = NSView()
    private var currentTabView: NSView?

    // Cached tab views (built once, reused)
    private var terminalView: NSView?
    private var shortcutsView: NSView?

    // Shortcuts tab state
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let actions = BindableAction.allCases
    private var recordingRow: Int? = nil
    private var eventMonitor: Any? = nil

    // Terminal tab controls (retained for commitTextFields / live-update)
    private var fontSizeField: NSTextField?
    private var shellField: NSTextField?
    private var historyField: NSTextField?

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 520))
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"

        view.wantsLayer = true
        view.layer?.backgroundColor = terminalBackground.cgColor

        // Segmented control
        segmentedControl.segmentCount = 2
        segmentedControl.setLabel("Terminal", forSegment: 0)
        segmentedControl.setLabel("Shortcuts", forSegment: 1)
        segmentedControl.segmentStyle = .texturedRounded
        segmentedControl.selectedSegment = 0
        segmentedControl.target = self
        segmentedControl.action = #selector(segmentChanged(_:))
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentedControl)

        // Content container
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)

        // Done button
        let doneButton = NSButton(title: "Done", target: self, action: #selector(dismissSettings))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(doneButton)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            segmentedControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            contentContainer.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 16),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            contentContainer.bottomAnchor.constraint(equalTo: doneButton.topAnchor, constant: -16),

            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            doneButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
        ])

        showTab(0)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        cancelRecording()
        commitTextFields()
        applyAndRefreshMenu()
    }

    // MARK: - Tab Switching

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        cancelRecording()
        commitTextFields()
        showTab(sender.selectedSegment)
    }

    private func showTab(_ index: Int) {
        currentTabView?.removeFromSuperview()

        let tabView: NSView
        switch index {
        case 0:
            if terminalView == nil { terminalView = makeTerminalView() }
            tabView = terminalView!
        case 1:
            if shortcutsView == nil { shortcutsView = makeShortcutsView() }
            tabView = shortcutsView!
        default: return
        }

        tabView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            tabView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            tabView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        currentTabView = tabView
    }

    // MARK: - Terminal Tab

    private func makeTerminalView() -> NSView {
        let container = NSView()
        let settings = AppSettingsManager.shared

        // Font
        let fontLabel = makeLabel("Font:")
        let popup = NSPopUpButton()
        popup.translatesAutoresizingMaskIntoConstraints = false
        let monoFonts = monospaceFontFamilies()
        popup.addItems(withTitles: monoFonts)
        if let idx = monoFonts.firstIndex(of: settings.terminalFontName) {
            popup.selectItem(at: idx)
        }
        popup.target = self
        popup.action = #selector(fontChanged(_:))

        // Font Size
        let sizeLabel = makeLabel("Font Size:")
        let sizeField = NSTextField(labelWithString: "\(Int(settings.terminalFontSize))")
        sizeField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        sizeField.textColor = terminalForeground
        sizeField.translatesAutoresizingMaskIntoConstraints = false
        fontSizeField = sizeField

        let stepper = NSStepper()
        stepper.minValue = 8
        stepper.maxValue = 24
        stepper.integerValue = Int(settings.terminalFontSize)
        stepper.increment = 1
        stepper.target = self
        stepper.action = #selector(fontSizeStepperChanged(_:))
        stepper.translatesAutoresizingMaskIntoConstraints = false

        // Shell
        let shellLabel = makeLabel("Shell:")
        let shellF = NSTextField()
        shellF.stringValue = settings.shell
        shellF.placeholderString = "/bin/zsh"
        shellF.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        shellF.translatesAutoresizingMaskIntoConstraints = false
        shellF.target = self
        shellF.action = #selector(shellChanged(_:))
        shellField = shellF

        // History Limit
        let histLabel = makeLabel("Tmux History Limit:")
        let histF = NSTextField()
        histF.stringValue = "\(settings.historyLimit)"
        histF.placeholderString = "50000"
        histF.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        histF.translatesAutoresizingMaskIntoConstraints = false
        histF.target = self
        histF.action = #selector(historyLimitChanged(_:))
        historyField = histF

        for v: NSView in [fontLabel, popup, sizeLabel, sizeField, stepper, shellLabel, shellF, histLabel, histF] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }

        NSLayoutConstraint.activate([
            fontLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            fontLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            popup.topAnchor.constraint(equalTo: fontLabel.bottomAnchor, constant: 6),
            popup.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            popup.widthAnchor.constraint(equalToConstant: 240),

            sizeLabel.topAnchor.constraint(equalTo: popup.bottomAnchor, constant: 20),
            sizeLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            sizeField.topAnchor.constraint(equalTo: sizeLabel.bottomAnchor, constant: 6),
            sizeField.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            stepper.centerYAnchor.constraint(equalTo: sizeField.centerYAnchor),
            stepper.leadingAnchor.constraint(equalTo: sizeField.trailingAnchor, constant: 8),

            shellLabel.topAnchor.constraint(equalTo: sizeField.bottomAnchor, constant: 20),
            shellLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            shellF.topAnchor.constraint(equalTo: shellLabel.bottomAnchor, constant: 6),
            shellF.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            shellF.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            histLabel.topAnchor.constraint(equalTo: shellF.bottomAnchor, constant: 20),
            histLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            histF.topAnchor.constraint(equalTo: histLabel.bottomAnchor, constant: 6),
            histF.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            histF.widthAnchor.constraint(equalToConstant: 120),
        ])

        return container
    }

    @objc private func fontChanged(_ sender: NSPopUpButton) {
        guard let name = sender.titleOfSelectedItem else { return }
        AppSettingsManager.shared.terminalFontName = name
    }

    @objc private func fontSizeStepperChanged(_ sender: NSStepper) {
        fontSizeField?.stringValue = "\(sender.integerValue)"
        AppSettingsManager.shared.terminalFontSize = CGFloat(sender.integerValue)
    }

    @objc private func shellChanged(_ sender: NSTextField) {
        let value = sender.stringValue.trimmingCharacters(in: .whitespaces)
        if value.isEmpty {
            AppSettingsManager.shared.shell = AppSettingsManager.defaultShell
        } else if FileManager.default.isExecutableFile(atPath: value) {
            AppSettingsManager.shared.shell = value
        } else {
            showAlert("Invalid Shell", "'\(value)' is not an executable file.")
            sender.stringValue = AppSettingsManager.shared.shell
        }
    }

    @objc private func historyLimitChanged(_ sender: NSTextField) {
        if let value = Int(sender.stringValue), value > 0 {
            AppSettingsManager.shared.historyLimit = value
        } else {
            sender.stringValue = "\(AppSettingsManager.shared.historyLimit)"
        }
    }

    private func monospaceFontFamilies() -> [String] {
        let fm = NSFontManager.shared
        let all = fm.availableFontFamilies
        return all.filter { family in
            guard let members = fm.availableMembers(ofFontFamily: family),
                  let first = members.first,
                  let fontName = first[0] as? String,
                  let font = NSFont(name: fontName, size: 13) else { return false }
            return font.isFixedPitch
        }.sorted()
    }

    // MARK: - Shortcuts Tab

    private func makeShortcutsView() -> NSView {
        let container = NSView()

        // Table setup
        let actionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionColumn.title = "Action"
        actionColumn.width = 180

        let shortcutColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shortcut"))
        shortcutColumn.title = "Shortcut"
        shortcutColumn.width = 120

        let recordColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("record"))
        recordColumn.title = ""
        recordColumn.width = 100

        // Remove old columns and add fresh ones
        for col in tableView.tableColumns {
            tableView.removeTableColumn(col)
        }
        tableView.addTableColumn(actionColumn)
        tableView.addTableColumn(shortcutColumn)
        tableView.addTableColumn(recordColumn)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowSizeStyle = .medium
        tableView.backgroundColor = terminalBackground
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.headerView?.wantsLayer = true
        tableView.reloadData()

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)

        // Reset button at bottom of shortcuts tab
        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetAllDefaults))
        resetButton.bezelStyle = .rounded
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(resetButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: resetButton.topAnchor, constant: -8),

            resetButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            resetButton.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    // MARK: - Helpers

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = terminalForeground
        return label
    }

    private func commitTextFields() {
        // Commit any in-flight text field edits
        if let field = shellField {
            shellChanged(field)
        }
        if let field = historyField {
            historyLimitChanged(field)
        }
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
        // commitTextFields + applyAndRefreshMenu handled by viewWillDisappear
        dismiss(nil)
    }

    @objc private func recordButtonClicked(_ sender: NSButton) {
        let row = sender.tag
        let action = actions[row]

        // Cmd+Q cannot be rebound
        if action == .quit {
            let alert = NSAlert()
            alert.messageText = "Cannot Rebind Quit"
            alert.informativeText = "\u{2318}Q is reserved and cannot be changed."
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        cancelRecording()
        recordingRow = row
        sender.title = "Press key\u{2026}"

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecordedKey(event)
            return nil  // consume the event
        }
    }

    // MARK: - Key Recording

    private func handleRecordedKey(_ event: NSEvent) {
        guard let row = recordingRow else { return }
        let action = actions[row]

        // Escape cancels recording
        if event.keyCode == 53 {
            cancelRecording()
            return
        }

        let key = event.charactersIgnoringModifiers ?? ""
        let mods = event.modifierFlags.intersection([.command, .option, .shift, .control])

        // Must include at least Cmd or Ctrl
        guard mods.contains(.command) || mods.contains(.control) else {
            cancelRecording()
            showAlert("Invalid Shortcut", "Shortcuts must include \u{2318} or \u{2303}.")
            return
        }

        guard !key.isEmpty else {
            cancelRecording()
            return
        }

        // Check for conflict with reserved shortcuts (Edit menu)
        if let reservedName = KeybindingManager.shared.findReservedConflict(keyEquivalent: key, modifiers: mods) {
            cancelRecording()
            let shortcutStr = KeybindingManager.displayString(keyEquivalent: key, modifiers: mods)
            showAlert("Shortcut Conflict", "\(shortcutStr) is reserved for \"\(reservedName)\".")
            return
        }

        // Check for conflict with other bindable actions
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

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
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
                button.title = "Press key\u{2026}"
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
