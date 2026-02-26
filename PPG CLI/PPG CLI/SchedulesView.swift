import AppKit

// MARK: - Data Model

struct ScheduleInfo {
    let name: String
    let cronExpression: String
    let type: String          // "swarm" or "prompt"
    let target: String        // swarm/prompt template name
    let projectRoot: String
    let projectName: String
    let filePath: String      // path to schedules.yaml
    let vars: [(String, String)]
}

// MARK: - SchedulesView

class SchedulesView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextStorageDelegate {

    private let splitView = NSSplitView()
    private let listScrollView = NSScrollView()
    private let tableView = NSTableView()
    private let editorScrollView = NSScrollView()
    private let editorTextView = NSTextView()
    private let headerLabel = NSTextField(labelWithString: "Schedules (0)")
    private let newButton = NSButton()
    private let daemonButton = NSButton()
    private let daemonDot = NSView()
    private let saveButton = NSButton()
    private let deleteButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "No schedules found")

    private var schedules: [ScheduleInfo] = []
    private var selectedIndex: Int? = nil
    private var isDirty = false
    /// Tracks which schedules.yaml file is loaded in the editor.
    private var loadedFilePath: String? = nil
    private var daemonRunning = false
    private var projects: [ProjectContext] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    // MARK: - Configure

    func configure(projects: [ProjectContext]) {
        self.projects = projects
        schedules = Self.scanSchedules(projects: projects)
        headerLabel.stringValue = "Schedules (\(schedules.count))"
        tableView.reloadData()
        emptyLabel.isHidden = !schedules.isEmpty
        if let idx = selectedIndex, idx < schedules.count {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        } else {
            selectedIndex = nil
            editorTextView.string = ""
            loadedFilePath = nil
            saveButton.isEnabled = false
            deleteButton.isEnabled = false
        }
        checkDaemonStatus()
    }

    // MARK: - File Scanning

    static func scanSchedules(projects: [ProjectContext]) -> [ScheduleInfo] {
        let fm = FileManager.default
        var results: [ScheduleInfo] = []

        for ctx in projects {
            let filePath = (ctx.projectRoot as NSString).appendingPathComponent(".ppg/schedules.yaml")
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

            let entries = parseSchedulesYAML(content)
            for entry in entries {
                results.append(ScheduleInfo(
                    name: entry.name,
                    cronExpression: entry.cron,
                    type: entry.type,
                    target: entry.target,
                    projectRoot: ctx.projectRoot,
                    projectName: ctx.projectName,
                    filePath: filePath,
                    vars: entry.vars
                ))
            }
        }
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Simple YAML Parser

    private struct ParsedSchedule {
        var name: String
        var cron: String
        var type: String    // "swarm" or "prompt"
        var target: String
        var vars: [(String, String)]
    }

    private static func parseSchedulesYAML(_ content: String) -> [ParsedSchedule] {
        var results: [ParsedSchedule] = []
        let lines = content.components(separatedBy: .newlines)

        var inSchedules = false
        var current: ParsedSchedule? = nil
        var inVars = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Top-level key
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") && !line.hasPrefix("-") {
                if let c = current {
                    results.append(c)
                    current = nil
                }
                inVars = false
                if trimmed.hasPrefix("schedules:") {
                    inSchedules = true
                } else {
                    inSchedules = false
                }
                continue
            }

            guard inSchedules else { continue }

            if trimmed.hasPrefix("- ") || trimmed == "-" {
                if let c = current {
                    results.append(c)
                }
                current = ParsedSchedule(name: "", cron: "", type: "", target: "", vars: [])
                inVars = false
                // Handle inline key on the dash line: "- name: foo"
                let afterDash = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !afterDash.isEmpty {
                    applyKeyValue(afterDash, to: &current!, inVars: &inVars)
                }
            } else if current != nil {
                applyKeyValue(trimmed, to: &current!, inVars: &inVars)
            }
        }
        if let c = current {
            results.append(c)
        }
        return results
    }

    private static func applyKeyValue(_ trimmed: String, to entry: inout ParsedSchedule, inVars: inout Bool) {
        if trimmed.hasPrefix("name:") {
            entry.name = yamlValue(trimmed)
            inVars = false
        } else if trimmed.hasPrefix("cron:") {
            entry.cron = yamlValue(trimmed)
            inVars = false
        } else if trimmed.hasPrefix("swarm:") {
            entry.type = "swarm"
            entry.target = yamlValue(trimmed)
            inVars = false
        } else if trimmed.hasPrefix("prompt:") {
            entry.type = "prompt"
            entry.target = yamlValue(trimmed)
            inVars = false
        } else if trimmed.hasPrefix("vars:") {
            inVars = true
        } else if inVars && trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let k = parts[0].trimmingCharacters(in: .whitespaces)
                let v = parts[1].trimmingCharacters(in: .whitespaces)
                entry.vars.append((k, stripQuotes(v)))
            }
        }
    }

    private static func yamlValue(_ line: String) -> String {
        guard let colonIdx = line.range(of: ":") else { return "" }
        var value = String(line[colonIdx.upperBound...]).trimmingCharacters(in: .whitespaces)
        value = stripQuotes(value)
        return value
    }

    private static func stripQuotes(_ s: String) -> String {
        var value = s
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    // MARK: - Daemon Status

    private func checkDaemonStatus() {
        guard let ctx = projects.first else {
            updateDaemonUI(running: false)
            return
        }
        let projectRoot = ctx.projectRoot
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = PPGService.shared.runPPGCommand("cron status --json", projectRoot: projectRoot)
            let running = result.stdout.contains("\"running\":true") || result.stdout.contains("\"running\": true")
            DispatchQueue.main.async {
                self?.updateDaemonUI(running: running)
            }
        }
    }

    private func updateDaemonUI(running: Bool) {
        daemonRunning = running
        daemonDot.wantsLayer = true
        daemonDot.layer?.cornerRadius = 5
        if running {
            daemonDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
            daemonButton.title = "Stop Daemon"
        } else {
            daemonDot.layer?.backgroundColor = NSColor.systemRed.cgColor
            daemonButton.title = "Start Daemon"
        }
    }

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = Theme.contentBackground.resolvedCGColor(for: effectiveAppearance)

        // Header
        let headerBar = NSView()
        headerBar.translatesAutoresizingMaskIntoConstraints = false

        headerLabel.font = .boldSystemFont(ofSize: 14)
        headerLabel.textColor = Theme.primaryText
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(headerLabel)

        // Daemon status dot
        daemonDot.translatesAutoresizingMaskIntoConstraints = false
        daemonDot.wantsLayer = true
        daemonDot.layer?.cornerRadius = 5
        daemonDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        headerBar.addSubview(daemonDot)

        // Daemon start/stop button
        daemonButton.bezelStyle = .accessoryBarAction
        daemonButton.title = "Start Daemon"
        daemonButton.font = .systemFont(ofSize: 11)
        daemonButton.isBordered = false
        daemonButton.contentTintColor = Theme.primaryText
        daemonButton.target = self
        daemonButton.action = #selector(daemonToggleClicked)
        daemonButton.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(daemonButton)

        newButton.bezelStyle = .accessoryBarAction
        newButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Schedule")
        newButton.title = "New Schedule"
        newButton.imagePosition = .imageLeading
        newButton.font = .systemFont(ofSize: 11)
        newButton.isBordered = false
        newButton.contentTintColor = Theme.primaryText
        newButton.target = self
        newButton.action = #selector(newScheduleClicked)
        newButton.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(newButton)

        let headerSep = NSBox()
        headerSep.boxType = .separator
        headerSep.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(headerSep)

        addSubview(headerBar)

        // Split view
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(splitView)

        // Left pane: table list
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("schedule"))
        column.title = ""
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowSizeStyle = .medium
        tableView.style = .sourceList
        tableView.backgroundColor = .clear

        listScrollView.documentView = tableView
        listScrollView.hasVerticalScroller = true
        listScrollView.drawsBackground = false
        splitView.addSubview(listScrollView)

        // Right pane: YAML editor
        let editorContainer = NSView()
        editorContainer.translatesAutoresizingMaskIntoConstraints = false

        editorTextView.isEditable = true
        editorTextView.isSelectable = true
        editorTextView.isRichText = false
        editorTextView.allowsUndo = true
        editorTextView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        editorTextView.backgroundColor = Theme.contentBackground
        editorTextView.textColor = Theme.primaryText
        editorTextView.insertionPointColor = Theme.primaryText
        editorTextView.isVerticallyResizable = true
        editorTextView.isHorizontallyResizable = false
        editorTextView.textContainer?.widthTracksTextView = true
        editorTextView.textContainerInset = NSSize(width: 8, height: 8)
        editorTextView.autoresizingMask = [.width, .height]
        editorTextView.textStorage?.delegate = self

        editorScrollView.documentView = editorTextView
        editorScrollView.hasVerticalScroller = true
        editorScrollView.drawsBackground = true
        editorScrollView.backgroundColor = Theme.contentBackground
        editorScrollView.translatesAutoresizingMaskIntoConstraints = false
        editorContainer.addSubview(editorScrollView)

        // Button bar at bottom of editor
        let buttonBar = NSView()
        buttonBar.translatesAutoresizingMaskIntoConstraints = false

        let btnSep = NSBox()
        btnSep.boxType = .separator
        btnSep.translatesAutoresizingMaskIntoConstraints = false
        buttonBar.addSubview(btnSep)

        saveButton.bezelStyle = .accessoryBarAction
        saveButton.title = "Save"
        saveButton.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")
        saveButton.imagePosition = .imageLeading
        saveButton.font = .systemFont(ofSize: 11)
        saveButton.isBordered = false
        saveButton.contentTintColor = Theme.primaryText
        saveButton.target = self
        saveButton.action = #selector(saveClicked)
        saveButton.isEnabled = false
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        buttonBar.addSubview(saveButton)

        deleteButton.bezelStyle = .accessoryBarAction
        deleteButton.title = "Delete"
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
        deleteButton.imagePosition = .imageLeading
        deleteButton.font = .systemFont(ofSize: 11)
        deleteButton.isBordered = false
        deleteButton.contentTintColor = .systemRed
        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)
        deleteButton.isEnabled = false
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        buttonBar.addSubview(deleteButton)

        editorContainer.addSubview(buttonBar)

        NSLayoutConstraint.activate([
            editorScrollView.topAnchor.constraint(equalTo: editorContainer.topAnchor),
            editorScrollView.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            editorScrollView.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
            editorScrollView.bottomAnchor.constraint(equalTo: buttonBar.topAnchor),

            buttonBar.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            buttonBar.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
            buttonBar.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor),
            buttonBar.heightAnchor.constraint(equalToConstant: 36),

            btnSep.topAnchor.constraint(equalTo: buttonBar.topAnchor),
            btnSep.leadingAnchor.constraint(equalTo: buttonBar.leadingAnchor),
            btnSep.trailingAnchor.constraint(equalTo: buttonBar.trailingAnchor),

            saveButton.leadingAnchor.constraint(equalTo: buttonBar.leadingAnchor, constant: 8),
            saveButton.centerYAnchor.constraint(equalTo: buttonBar.centerYAnchor),

            deleteButton.trailingAnchor.constraint(equalTo: buttonBar.trailingAnchor, constant: -8),
            deleteButton.centerYAnchor.constraint(equalTo: buttonBar.centerYAnchor),
        ])

        splitView.addSubview(editorContainer)

        // Empty label
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 36),

            headerLabel.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 12),
            headerLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            daemonDot.leadingAnchor.constraint(equalTo: headerLabel.trailingAnchor, constant: 8),
            daemonDot.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            daemonDot.widthAnchor.constraint(equalToConstant: 10),
            daemonDot.heightAnchor.constraint(equalToConstant: 10),

            daemonButton.leadingAnchor.constraint(equalTo: daemonDot.trailingAnchor, constant: 4),
            daemonButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            newButton.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -8),
            newButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            headerSep.bottomAnchor.constraint(equalTo: headerBar.bottomAnchor),
            headerSep.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            headerSep.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),

            splitView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Set initial split position
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.splitView.setPosition(220, ofDividerAt: 0)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.contentBackground.resolvedCGColor(for: effectiveAppearance)
        editorTextView.backgroundColor = Theme.contentBackground
        editorScrollView.backgroundColor = Theme.contentBackground
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        schedules.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < schedules.count else { return nil }
        let schedule = schedules[row]

        let cell = NSTableCellView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: schedule.name)
        nameLabel.font = .boldSystemFont(ofSize: 12)
        nameLabel.textColor = Theme.primaryText

        let typeIcon = schedule.type == "swarm" ? "S" : "P"
        let detail = "[\(typeIcon)] \(schedule.cronExpression) \u{2192} \(schedule.target)"
        let detailLabel = NSTextField(labelWithString: "\(schedule.projectName) \u{00B7} \(detail)")
        detailLabel.font = .systemFont(ofSize: 10)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        stack.addArrangedSubview(nameLabel)
        stack.addArrangedSubview(detailLabel)

        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        38
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < schedules.count else {
            selectedIndex = nil
            editorTextView.string = ""
            loadedFilePath = nil
            saveButton.isEnabled = false
            deleteButton.isEnabled = false
            return
        }
        selectedIndex = row
        loadScheduleFile(at: row)
        saveButton.isEnabled = true
        deleteButton.isEnabled = true
    }

    // MARK: - Editor

    private func loadScheduleFile(at index: Int) {
        let schedule = schedules[index]
        let content = (try? String(contentsOfFile: schedule.filePath, encoding: .utf8)) ?? ""
        editorTextView.string = content
        loadedFilePath = schedule.filePath
        isDirty = false
        highlightYAML()
    }

    // MARK: - NSTextStorageDelegate (YAML key highlighting)

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        isDirty = true
        highlightYAML()
    }

    private func highlightYAML() {
        guard let storage = editorTextView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)

        storage.beginEditing()
        storage.addAttributes([
            .foregroundColor: Theme.primaryText,
            .font: monoFont,
        ], range: fullRange)

        let text = storage.string

        // Highlight YAML keys (word followed by colon at start of line or after spaces)
        if let keyRegex = try? NSRegularExpression(pattern: "^(\\s*-?\\s*)(\\w+):", options: .anchorsMatchLines) {
            let matches = keyRegex.matches(in: text, range: fullRange)
            for match in matches {
                if match.numberOfRanges > 2 {
                    storage.addAttributes([
                        .foregroundColor: NSColor.systemBlue,
                        .font: boldFont,
                    ], range: match.range(at: 2))
                }
            }
        }

        // Highlight cron expressions (quoted strings)
        if let quotedRegex = try? NSRegularExpression(pattern: "'[^']*'|\"[^\"]*\"") {
            let matches = quotedRegex.matches(in: text, range: fullRange)
            for match in matches {
                storage.addAttributes([
                    .foregroundColor: NSColor.systemOrange,
                    .font: monoFont,
                ], range: match.range)
            }
        }

        storage.endEditing()
    }

    // MARK: - Actions

    @objc private func saveClicked() {
        guard let path = loadedFilePath else { return }
        let content = editorTextView.string
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            isDirty = false
            // Rescan to update the list
            configure(projects: projects)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to Save"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func deleteClicked() {
        guard let idx = selectedIndex, idx < schedules.count else { return }
        let schedule = schedules[idx]

        let alert = NSAlert()
        alert.messageText = "Delete schedule \"\(schedule.name)\"?"
        alert.informativeText = "This will remove the schedule entry from schedules.yaml. If it's the only entry, the file will be deleted."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Remove the entry from the YAML by filtering out lines for this schedule
        // Simplest approach: reload, remove the schedule block, save
        guard let content = try? String(contentsOfFile: schedule.filePath, encoding: .utf8) else { return }
        let filtered = removeScheduleEntry(named: schedule.name, from: content)

        do {
            if filtered.trimmingCharacters(in: .whitespacesAndNewlines) == "schedules:" ||
               filtered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try FileManager.default.removeItem(atPath: schedule.filePath)
            } else {
                try filtered.write(toFile: schedule.filePath, atomically: true, encoding: .utf8)
            }
            selectedIndex = nil
            editorTextView.string = ""
            loadedFilePath = nil
            saveButton.isEnabled = false
            deleteButton.isEnabled = false
            configure(projects: projects)
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Failed to Delete"
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .warning
            errAlert.runModal()
        }
    }

    /// Remove a named schedule entry from the YAML content.
    private func removeScheduleEntry(named name: String, from content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        var skipping = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Detect start of a schedule entry (list item)
            if trimmed.hasPrefix("- ") && (trimmed.contains("name:") && trimmed.contains(name)) {
                skipping = true
                continue
            }
            if trimmed.hasPrefix("- name:") && Self.yamlValue(trimmed.replacingOccurrences(of: "- ", with: "")) == name {
                skipping = true
                continue
            }
            // If we're in a "- name: X" block, detect the start of the entry
            if trimmed == "- name: \(name)" || trimmed == "- name: '\(name)'" || trimmed == "- name: \"\(name)\"" {
                skipping = true
                continue
            }
            // Stop skipping when we hit the next list item or a top-level key
            if skipping {
                if trimmed.hasPrefix("- ") || (!line.hasPrefix(" ") && !line.hasPrefix("\t") && !trimmed.isEmpty && !trimmed.hasPrefix("#")) {
                    skipping = false
                } else {
                    continue
                }
            }
            result.append(line)
        }
        return result.joined(separator: "\n")
    }

    @objc private func daemonToggleClicked() {
        guard let ctx = projects.first else { return }
        let command = daemonRunning ? "cron stop" : "cron start"
        let projectRoot = ctx.projectRoot
        daemonButton.isEnabled = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = PPGService.shared.runPPGCommand(command, projectRoot: projectRoot)
            DispatchQueue.main.async {
                self?.daemonButton.isEnabled = true
                self?.checkDaemonStatus()
            }
        }
    }

    @objc private func newScheduleClicked() {
        guard !projects.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "New Schedule"
        alert.informativeText = ""
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 260))

        var y: CGFloat = 260

        func addLabel(_ text: String) {
            y -= 16
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 0, y: y, width: 260, height: 16)
            accessory.addSubview(label)
            y -= 2
        }

        func addPopup(_ items: [String]) -> NSPopUpButton {
            y -= 24
            let popup = NSPopUpButton(frame: NSRect(x: 0, y: y, width: 260, height: 24), pullsDown: false)
            for item in items { popup.addItem(withTitle: item) }
            accessory.addSubview(popup)
            y -= 8
            return popup
        }

        addLabel("Name:")
        y -= 24
        let nameField = NSTextField(frame: NSRect(x: 0, y: y, width: 260, height: 24))
        nameField.placeholderString = "schedule-name"
        accessory.addSubview(nameField)
        y -= 12

        addLabel("Cron Expression:")
        y -= 24
        let cronField = NSTextField(frame: NSRect(x: 0, y: y, width: 260, height: 24))
        cronField.placeholderString = "0 * * * *"
        accessory.addSubview(cronField)
        y -= 12

        addLabel("Type:")
        let typePopup = addPopup(["swarm", "prompt"])

        addLabel("Target (template name):")
        y -= 24
        let targetField = NSTextField(frame: NSRect(x: 0, y: y, width: 260, height: 24))
        targetField.placeholderString = "template-name"
        accessory.addSubview(targetField)
        y -= 12

        addLabel("Project:")
        let projectPopup = addPopup(projects.map { $0.projectName.isEmpty ? $0.projectRoot : $0.projectName })

        alert.accessoryView = accessory
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let cron = cronField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !cron.isEmpty else { return }
        let type = typePopup.titleOfSelectedItem ?? "swarm"
        let target = targetField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }

        let projectIdx = projectPopup.indexOfSelectedItem
        guard projectIdx >= 0, projectIdx < projects.count else { return }
        let ctx = projects[projectIdx]

        let ppgDir = (ctx.projectRoot as NSString).appendingPathComponent(".ppg")
        let fm = FileManager.default
        if !fm.fileExists(atPath: ppgDir) {
            try? fm.createDirectory(atPath: ppgDir, withIntermediateDirectories: true)
        }

        let filePath = (ppgDir as NSString).appendingPathComponent("schedules.yaml")

        // Build the new entry YAML
        let entry = "  - name: \(name)\n    \(type): \(target)\n    cron: '\(cron)'\n"

        do {
            if fm.fileExists(atPath: filePath),
               let existing = try? String(contentsOfFile: filePath, encoding: .utf8) {
                // Append to existing file
                let updated = existing.hasSuffix("\n") ? existing + entry : existing + "\n" + entry
                try updated.write(toFile: filePath, atomically: true, encoding: .utf8)
            } else {
                // Create new file
                let content = "schedules:\n" + entry
                try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            }

            configure(projects: projects)
            // Select the new schedule
            if let idx = schedules.firstIndex(where: { $0.name == name && $0.filePath == filePath }) {
                tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
                loadScheduleFile(at: idx)
                selectedIndex = idx
            }
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Failed to Create"
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .warning
            errAlert.runModal()
        }
    }
}
