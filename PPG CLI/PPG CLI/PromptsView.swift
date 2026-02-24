import AppKit

// MARK: - Data Model

struct PromptFileInfo {
    let name: String            // filename without .md
    let path: String            // absolute path
    let projectRoot: String
    let projectName: String
    let directory: String       // "prompts" or "templates"
    let firstLine: String       // first non-empty line as description
    let variables: [String]     // detected {{VAR}} names
}

// MARK: - PromptsView

class PromptsView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextStorageDelegate {

    private let splitView = NSSplitView()
    private let listScrollView = NSScrollView()
    private let tableView = NSTableView()
    private let editorScrollView = NSScrollView()
    private let editorTextView = NSTextView()
    private let headerLabel = NSTextField(labelWithString: "Prompts (0)")
    private let newButton = NSButton()
    private let saveButton = NSButton()
    private let deleteButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "No prompts found")

    private var prompts: [PromptFileInfo] = []
    private var selectedIndex: Int? = nil
    private var isDirty = false

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
        prompts = Self.scanPrompts(projects: projects)
        headerLabel.stringValue = "Prompts (\(prompts.count))"
        tableView.reloadData()
        emptyLabel.isHidden = !prompts.isEmpty
        if let idx = selectedIndex, idx < prompts.count {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        } else {
            selectedIndex = nil
            editorTextView.string = ""
            saveButton.isEnabled = false
            deleteButton.isEnabled = false
        }
    }

    // MARK: - File Scanning

    static func scanPrompts(projects: [ProjectContext]) -> [PromptFileInfo] {
        let fm = FileManager.default
        var results: [PromptFileInfo] = []
        let varRegex = try! NSRegularExpression(pattern: "\\{\\{(\\w+)\\}\\}")

        for ctx in projects {
            let pgDir = (ctx.projectRoot as NSString).appendingPathComponent(".pg")
            for dir in ["prompts", "templates"] {
                let folder = (pgDir as NSString).appendingPathComponent(dir)
                guard let files = try? fm.contentsOfDirectory(atPath: folder) else { continue }
                for file in files where file.hasSuffix(".md") {
                    let path = (folder as NSString).appendingPathComponent(file)
                    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

                    let name = (file as NSString).deletingPathExtension
                    let firstLine = content.components(separatedBy: .newlines)
                        .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
                        .trimmingCharacters(in: .whitespaces) ?? ""

                    let range = NSRange(content.startIndex..., in: content)
                    let matches = varRegex.matches(in: content, range: range)
                    var vars: [String] = []
                    var seen = Set<String>()
                    for match in matches {
                        if let r = Range(match.range(at: 1), in: content) {
                            let v = String(content[r])
                            if !seen.contains(v) {
                                seen.insert(v)
                                vars.append(v)
                            }
                        }
                    }

                    results.append(PromptFileInfo(
                        name: name,
                        path: path,
                        projectRoot: ctx.projectRoot,
                        projectName: ctx.projectName,
                        directory: dir,
                        firstLine: firstLine,
                        variables: vars
                    ))
                }
            }
        }
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = terminalBackground.cgColor

        // Header
        let headerBar = NSView()
        headerBar.translatesAutoresizingMaskIntoConstraints = false

        headerLabel.font = .boldSystemFont(ofSize: 14)
        headerLabel.textColor = terminalForeground
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(headerLabel)

        newButton.bezelStyle = .accessoryBarAction
        newButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Prompt")
        newButton.title = "New Prompt"
        newButton.imagePosition = .imageLeading
        newButton.font = .systemFont(ofSize: 11)
        newButton.isBordered = false
        newButton.contentTintColor = terminalForeground
        newButton.target = self
        newButton.action = #selector(newPromptClicked)
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
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("prompt"))
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

        // Right pane: editor
        let editorContainer = NSView()
        editorContainer.translatesAutoresizingMaskIntoConstraints = false

        editorTextView.isEditable = true
        editorTextView.isSelectable = true
        editorTextView.isRichText = false
        editorTextView.allowsUndo = true
        editorTextView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        editorTextView.backgroundColor = terminalBackground
        editorTextView.textColor = terminalForeground
        editorTextView.insertionPointColor = terminalForeground
        editorTextView.isVerticallyResizable = true
        editorTextView.isHorizontallyResizable = false
        editorTextView.textContainer?.widthTracksTextView = true
        editorTextView.textContainerInset = NSSize(width: 8, height: 8)
        editorTextView.autoresizingMask = [.width, .height]
        editorTextView.textStorage?.delegate = self

        editorScrollView.documentView = editorTextView
        editorScrollView.hasVerticalScroller = true
        editorScrollView.drawsBackground = true
        editorScrollView.backgroundColor = terminalBackground
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
        saveButton.contentTintColor = terminalForeground
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

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        prompts.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < prompts.count else { return nil }
        let prompt = prompts[row]

        let cell = NSTableCellView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: prompt.name)
        nameLabel.font = .boldSystemFont(ofSize: 12)
        nameLabel.textColor = terminalForeground

        let detailParts = [prompt.projectName, prompt.directory]
        let varPart = prompt.variables.isEmpty ? "" : " · \(prompt.variables.map { "{{\($0)}}" }.joined(separator: " "))"
        let detailLabel = NSTextField(labelWithString: detailParts.joined(separator: " · ") + varPart)
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
        guard row >= 0, row < prompts.count else {
            selectedIndex = nil
            editorTextView.string = ""
            saveButton.isEnabled = false
            deleteButton.isEnabled = false
            return
        }
        selectedIndex = row
        loadPromptContent(at: row)
        saveButton.isEnabled = true
        deleteButton.isEnabled = true
    }

    // MARK: - Editor

    private func loadPromptContent(at index: Int) {
        let prompt = prompts[index]
        let content = (try? String(contentsOfFile: prompt.path, encoding: .utf8)) ?? ""
        editorTextView.string = content
        isDirty = false
        highlightVariables()
    }

    // MARK: - NSTextStorageDelegate ({{VAR}} highlighting)

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        isDirty = true
        highlightVariables()
    }

    private func highlightVariables() {
        guard let storage = editorTextView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)

        storage.beginEditing()
        storage.addAttributes([
            .foregroundColor: terminalForeground,
            .font: monoFont,
        ], range: fullRange)

        let text = storage.string
        let regex = try! NSRegularExpression(pattern: "\\{\\{\\w+\\}\\}")
        let matches = regex.matches(in: text, range: fullRange)
        for match in matches {
            storage.addAttributes([
                .foregroundColor: NSColor.systemOrange,
                .font: boldFont,
            ], range: match.range)
        }
        storage.endEditing()
    }

    // MARK: - Actions

    @objc private func saveClicked() {
        guard let idx = selectedIndex, idx < prompts.count else { return }
        let prompt = prompts[idx]
        let content = editorTextView.string
        do {
            try content.write(toFile: prompt.path, atomically: true, encoding: .utf8)
            isDirty = false
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to Save"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func deleteClicked() {
        guard let idx = selectedIndex, idx < prompts.count else { return }
        let prompt = prompts[idx]

        let alert = NSAlert()
        alert.messageText = "Delete \"\(prompt.name)\"?"
        alert.informativeText = "This will permanently delete the prompt file."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try FileManager.default.removeItem(atPath: prompt.path)
            prompts.remove(at: idx)
            headerLabel.stringValue = "Prompts (\(prompts.count))"
            selectedIndex = nil
            editorTextView.string = ""
            saveButton.isEnabled = false
            deleteButton.isEnabled = false
            tableView.reloadData()
            emptyLabel.isHidden = !prompts.isEmpty
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Failed to Delete"
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .warning
            errAlert.runModal()
        }
    }

    @objc private func newPromptClicked() {
        let projects = OpenProjects.shared.projects
        guard !projects.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "New Prompt"
        alert.informativeText = "Enter a name for the prompt file:"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let accessory = NSStackView()
        accessory.orientation = .vertical
        accessory.spacing = 8

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        nameField.placeholderString = "prompt-name"
        accessory.addArrangedSubview(nameField)

        let projectPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 24), pullsDown: false)
        for ctx in projects {
            projectPopup.addItem(withTitle: ctx.projectName.isEmpty ? ctx.projectRoot : ctx.projectName)
        }
        accessory.addArrangedSubview(projectPopup)

        let dirPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 24), pullsDown: false)
        dirPopup.addItem(withTitle: "prompts")
        dirPopup.addItem(withTitle: "templates")
        accessory.addArrangedSubview(dirPopup)

        accessory.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            accessory.widthAnchor.constraint(equalToConstant: 240),
        ])

        alert.accessoryView = accessory
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let projectIdx = projectPopup.indexOfSelectedItem
        guard projectIdx >= 0, projectIdx < projects.count else { return }
        let ctx = projects[projectIdx]
        let dir = dirPopup.titleOfSelectedItem ?? "prompts"

        let folder = (ctx.projectRoot as NSString).appendingPathComponent(".pg/\(dir)")
        let fm = FileManager.default
        if !fm.fileExists(atPath: folder) {
            try? fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }

        let filename = name.hasSuffix(".md") ? name : "\(name).md"
        let path = (folder as NSString).appendingPathComponent(filename)
        let skeleton = "# \(name)\n\nPrompt here.\n"

        do {
            try skeleton.write(toFile: path, atomically: true, encoding: .utf8)
            configure(projects: OpenProjects.shared.projects)
            // Select the new file
            if let idx = prompts.firstIndex(where: { $0.path == path }) {
                tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
                loadPromptContent(at: idx)
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
