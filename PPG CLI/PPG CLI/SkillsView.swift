import AppKit

// MARK: - Data Model

struct SkillFileInfo {
    let name: String            // skill directory name (kebab-case)
    let path: String            // path to SKILL.md
    let skillDir: String        // path to skill directory
    let description: String     // from YAML frontmatter
    let userInvocable: Bool     // from YAML frontmatter
    let body: String            // markdown body after frontmatter
    let referenceFiles: [String] // filenames in references/ subdirectory
}

// MARK: - SkillsView

class SkillsView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextStorageDelegate {

    private let splitView = NSSplitView()
    private let listScrollView = NSScrollView()
    private let tableView = NSTableView()
    private let detailScrollView = NSScrollView()
    private let detailStack = NSStackView()
    private let headerLabel = NSTextField(labelWithString: "Skills (0)")
    private let importButton = NSButton()
    private let newButton = NSButton()
    private let saveButton = NSButton()
    private let deleteButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "No skills found")

    // Detail form fields
    private let nameField = NSTextField()
    private let descField = NSTextField()
    private let invocableCheckbox = NSButton(checkboxWithTitle: "User-invocable", target: nil, action: nil)
    private let editorScrollView = NSScrollView()
    private let editorTextView = NSTextView()

    // Reference files
    private let refsLabel = NSTextField(labelWithString: "Reference Files:")
    private let refsScrollView = NSScrollView()
    private let refsTableView = NSTableView()
    private let addRefButton = NSButton()
    private let removeRefButton = NSButton()

    // Back-to-SKILL button (shown when editing a reference file)
    private let backButton = NSButton()
    private var editingRefFile: String? = nil
    private var pendingBodyText: String? = nil  // preserves unsaved editor content when switching to ref file

    private var skills: [SkillFileInfo] = []
    private var selectedIndex: Int? = nil

    // Transient state for the import dialog
    private var importTypePopup: NSPopUpButton?
    private var importItemPopup: NSPopUpButton?
    private var importNameInput: NSTextField?
    private var importPrompts: [PromptFileInfo] = []
    private var importSwarms: [SwarmFileInfo] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    // MARK: - Configure

    func configure() {
        skills = Self.scanSkills()
        headerLabel.stringValue = "Skills (\(skills.count))"
        tableView.reloadData()
        emptyLabel.isHidden = !skills.isEmpty
        if let idx = selectedIndex, idx < skills.count {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        } else {
            selectedIndex = nil
            clearDetailForm()
        }
    }

    // MARK: - File Scanning

    static func scanSkills() -> [SkillFileInfo] {
        let fm = FileManager.default
        let skillsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/skills")
        guard let dirs = try? fm.contentsOfDirectory(atPath: skillsDir) else { return [] }
        var results: [SkillFileInfo] = []
        for dir in dirs {
            let skillDir = (skillsDir as NSString).appendingPathComponent(dir)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: skillDir, isDirectory: &isDir), isDir.boolValue else { continue }
            let skillFile = (skillDir as NSString).appendingPathComponent("SKILL.md")
            guard let content = try? String(contentsOfFile: skillFile, encoding: .utf8) else { continue }
            let parsed = parseFrontmatter(content)
            // Scan references
            let refsDir = (skillDir as NSString).appendingPathComponent("references")
            let refFiles = (try? fm.contentsOfDirectory(atPath: refsDir))?.filter { $0.hasSuffix(".md") }.sorted() ?? []
            results.append(SkillFileInfo(
                name: dir, path: skillFile, skillDir: skillDir,
                description: parsed.description, userInvocable: parsed.userInvocable,
                body: parsed.body, referenceFiles: refFiles
            ))
        }
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Frontmatter Parsing

    static func parseFrontmatter(_ content: String) -> (name: String, description: String, userInvocable: Bool, body: String) {
        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return ("", "", false, content)
        }
        var name = "", description = "", userInvocable = false
        var endIdx = 1
        for i in 1..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { endIdx = i; break }
            if trimmed.hasPrefix("name:") {
                name = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("description:") {
                description = String(trimmed.dropFirst(12)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("user-invocable:") {
                let val = String(trimmed.dropFirst(15)).trimmingCharacters(in: .whitespaces).lowercased()
                userInvocable = val == "true" || val == "yes"
            }
        }
        let bodyLines = Array(lines.dropFirst(endIdx + 1))
        let body = bodyLines.joined(separator: "\n")
        return (name, description, userInvocable, body.drop(while: { $0.isNewline }).description)
    }

    // MARK: - Validation

    /// Returns nil if the name is valid, or an error message string if not.
    private static func validateFilename(_ name: String) -> String? {
        if name.isEmpty { return "Name cannot be empty." }
        if name.contains("/") || name.contains("\\") { return "Name cannot contain slashes." }
        if name == "." || name == ".." { return "Name cannot be '.' or '..'." }
        if name.hasPrefix(".") { return "Name cannot start with a dot." }
        if name.contains("\0") { return "Name contains invalid characters." }
        return nil
    }

    // MARK: - Serialization

    static func serializeSkill(name: String, description: String, userInvocable: Bool, body: String) -> String {
        var lines = ["---"]
        lines.append("name: \(name)")
        lines.append("description: \(description)")
        lines.append("user-invocable: \(userInvocable)")
        lines.append("---")
        lines.append("")
        lines.append(body)
        return lines.joined(separator: "\n")
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

        importButton.bezelStyle = .accessoryBarAction
        importButton.image = NSImage(systemSymbolName: "square.and.arrow.down.on.square", accessibilityDescription: "Import")
        importButton.title = "Import"
        importButton.imagePosition = .imageLeading
        importButton.font = .systemFont(ofSize: 11)
        importButton.isBordered = false
        importButton.contentTintColor = Theme.primaryText
        importButton.target = self
        importButton.action = #selector(importClicked)
        importButton.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(importButton)

        newButton.bezelStyle = .accessoryBarAction
        newButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Skill")
        newButton.title = "New Skill"
        newButton.imagePosition = .imageLeading
        newButton.font = .systemFont(ofSize: 11)
        newButton.isBordered = false
        newButton.contentTintColor = Theme.primaryText
        newButton.target = self
        newButton.action = #selector(newSkillClicked)
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
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("skill"))
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

        // Right pane: detail form
        let detailContainer = NSView()
        detailContainer.translatesAutoresizingMaskIntoConstraints = false

        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = 10
        detailStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        detailStack.translatesAutoresizingMaskIntoConstraints = false

        setupDetailForm()

        detailScrollView.documentView = detailStack
        detailScrollView.hasVerticalScroller = true
        detailScrollView.drawsBackground = true
        detailScrollView.backgroundColor = Theme.contentBackground
        detailScrollView.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(detailScrollView)

        // Button bar
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

        detailContainer.addSubview(buttonBar)

        NSLayoutConstraint.activate([
            detailScrollView.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            detailScrollView.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            detailScrollView.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            detailScrollView.bottomAnchor.constraint(equalTo: buttonBar.topAnchor),

            detailStack.leadingAnchor.constraint(equalTo: detailScrollView.contentView.leadingAnchor),
            detailStack.trailingAnchor.constraint(equalTo: detailScrollView.contentView.trailingAnchor),

            buttonBar.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            buttonBar.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            buttonBar.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),
            buttonBar.heightAnchor.constraint(equalToConstant: 36),

            btnSep.topAnchor.constraint(equalTo: buttonBar.topAnchor),
            btnSep.leadingAnchor.constraint(equalTo: buttonBar.leadingAnchor),
            btnSep.trailingAnchor.constraint(equalTo: buttonBar.trailingAnchor),

            saveButton.leadingAnchor.constraint(equalTo: buttonBar.leadingAnchor, constant: 8),
            saveButton.centerYAnchor.constraint(equalTo: buttonBar.centerYAnchor),

            deleteButton.trailingAnchor.constraint(equalTo: buttonBar.trailingAnchor, constant: -8),
            deleteButton.centerYAnchor.constraint(equalTo: buttonBar.centerYAnchor),
        ])

        splitView.addSubview(detailContainer)

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

            importButton.trailingAnchor.constraint(equalTo: newButton.leadingAnchor, constant: -4),
            importButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

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
        detailScrollView.backgroundColor = Theme.contentBackground
    }

    // MARK: - Detail Form Setup

    private func setupDetailForm() {
        // Name
        let nameRow = makeFormRow(label: "Name:", field: nameField)
        nameField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        nameField.textColor = Theme.primaryText
        nameField.backgroundColor = Theme.contentBackground
        nameField.drawsBackground = true
        nameField.placeholderString = "skill-name"
        detailStack.addArrangedSubview(nameRow)
        nameRow.translatesAutoresizingMaskIntoConstraints = false
        nameRow.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -24).isActive = true

        // Description
        let descRow = makeFormRow(label: "Description:", field: descField)
        descField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        descField.textColor = Theme.primaryText
        descField.backgroundColor = Theme.contentBackground
        descField.drawsBackground = true
        descField.placeholderString = "What this skill does"
        detailStack.addArrangedSubview(descRow)
        descRow.translatesAutoresizingMaskIntoConstraints = false
        descRow.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -24).isActive = true

        // User-invocable checkbox
        invocableCheckbox.contentTintColor = Theme.primaryText
        detailStack.addArrangedSubview(invocableCheckbox)

        // Back button (hidden by default)
        backButton.bezelStyle = .accessoryBarAction
        backButton.image = NSImage(systemSymbolName: "arrow.left", accessibilityDescription: "Back")
        backButton.title = "Back to SKILL.md"
        backButton.imagePosition = .imageLeading
        backButton.font = .systemFont(ofSize: 11)
        backButton.isBordered = false
        backButton.contentTintColor = Theme.primaryText
        backButton.target = self
        backButton.action = #selector(backToSkillClicked)
        backButton.isHidden = true
        detailStack.addArrangedSubview(backButton)

        // Body editor
        let editorLabel = NSTextField(labelWithString: "Body:")
        editorLabel.font = .boldSystemFont(ofSize: 12)
        editorLabel.textColor = Theme.primaryText
        detailStack.addArrangedSubview(editorLabel)

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

        editorScrollView.documentView = editorTextView
        editorScrollView.hasVerticalScroller = true
        editorScrollView.drawsBackground = true
        editorScrollView.backgroundColor = Theme.contentBackground
        editorScrollView.translatesAutoresizingMaskIntoConstraints = false
        detailStack.addArrangedSubview(editorScrollView)
        editorScrollView.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -24).isActive = true
        editorScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        // Reference Files section
        refsLabel.font = .boldSystemFont(ofSize: 12)
        refsLabel.textColor = Theme.primaryText
        detailStack.addArrangedSubview(refsLabel)

        let refsColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ref"))
        refsColumn.title = ""
        refsTableView.addTableColumn(refsColumn)
        refsTableView.headerView = nil
        refsTableView.dataSource = self
        refsTableView.delegate = self
        refsTableView.backgroundColor = .clear
        refsTableView.doubleAction = #selector(refDoubleClicked)
        refsTableView.target = self

        refsScrollView.documentView = refsTableView
        refsScrollView.hasVerticalScroller = true
        refsScrollView.drawsBackground = false
        refsScrollView.translatesAutoresizingMaskIntoConstraints = false
        detailStack.addArrangedSubview(refsScrollView)
        refsScrollView.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -24).isActive = true
        refsScrollView.heightAnchor.constraint(equalToConstant: 100).isActive = true

        // Add/Remove ref buttons
        addRefButton.bezelStyle = .accessoryBarAction
        addRefButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Reference")
        addRefButton.title = "Add"
        addRefButton.imagePosition = .imageLeading
        addRefButton.font = .systemFont(ofSize: 11)
        addRefButton.isBordered = false
        addRefButton.contentTintColor = Theme.primaryText
        addRefButton.target = self
        addRefButton.action = #selector(addRefClicked)

        removeRefButton.bezelStyle = .accessoryBarAction
        removeRefButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove Reference")
        removeRefButton.title = "Remove"
        removeRefButton.imagePosition = .imageLeading
        removeRefButton.font = .systemFont(ofSize: 11)
        removeRefButton.isBordered = false
        removeRefButton.contentTintColor = .systemRed
        removeRefButton.target = self
        removeRefButton.action = #selector(removeRefClicked)

        let refBtnStack = NSStackView(views: [addRefButton, removeRefButton])
        refBtnStack.orientation = .horizontal
        refBtnStack.spacing = 8
        detailStack.addArrangedSubview(refBtnStack)
    }

    private func makeFormRow(label: String, field: NSTextField) -> NSStackView {
        let labelView = NSTextField(labelWithString: label)
        labelView.font = .systemFont(ofSize: 12)
        labelView.textColor = .secondaryLabelColor
        labelView.setContentHuggingPriority(.required, for: .horizontal)

        field.isEditable = true
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel

        let row = NSStackView(views: [labelView, field])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tv: NSTableView) -> Int {
        if tv === refsTableView {
            guard let idx = selectedIndex, idx < skills.count else { return 0 }
            return skills[idx].referenceFiles.count
        }
        return skills.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tv: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tv === refsTableView {
            guard let idx = selectedIndex, idx < skills.count, row < skills[idx].referenceFiles.count else { return nil }
            let refName = skills[idx].referenceFiles[row]
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: refName)
            label.font = .systemFont(ofSize: 12)
            label.textColor = Theme.primaryText
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        guard row < skills.count else { return nil }
        let skill = skills[row]

        let cell = NSTableCellView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: skill.name)
        nameLabel.font = .boldSystemFont(ofSize: 12)
        nameLabel.textColor = Theme.primaryText

        var detailParts: [String] = []
        if !skill.description.isEmpty {
            let truncDesc = skill.description.count > 40 ? String(skill.description.prefix(40)) + "..." : skill.description
            detailParts.append(truncDesc)
        }
        if skill.userInvocable {
            detailParts.append("invocable")
        }
        let detailLabel = NSTextField(labelWithString: detailParts.joined(separator: " · "))
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

    func tableView(_ tv: NSTableView, heightOfRow row: Int) -> CGFloat {
        if tv === refsTableView { return 24 }
        return 38
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTableView, tv === tableView else { return }
        let row = tableView.selectedRow
        guard row >= 0, row < skills.count else {
            selectedIndex = nil
            clearDetailForm()
            return
        }
        selectedIndex = row
        loadSkillDetail(at: row)
        saveButton.isEnabled = true
        deleteButton.isEnabled = true
    }

    // MARK: - Detail Form

    private func loadSkillDetail(at index: Int) {
        let skill = skills[index]
        nameField.stringValue = skill.name
        descField.stringValue = skill.description
        invocableCheckbox.state = skill.userInvocable ? .on : .off
        editorTextView.string = skill.body
        editingRefFile = nil
        pendingBodyText = nil
        backButton.isHidden = true
        refsTableView.reloadData()
    }

    private func clearDetailForm() {
        nameField.stringValue = ""
        descField.stringValue = ""
        invocableCheckbox.state = .off
        editorTextView.string = ""
        editingRefFile = nil
        pendingBodyText = nil
        backButton.isHidden = true
        saveButton.isEnabled = false
        deleteButton.isEnabled = false
        refsTableView.reloadData()
    }

    // MARK: - Actions

    @objc private func saveClicked() {
        guard let idx = selectedIndex, idx < skills.count else { return }
        let skill = skills[idx]
        let fm = FileManager.default

        let newName = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else { return }

        if let validationError = Self.validateFilename(newName) {
            let errAlert = NSAlert()
            errAlert.messageText = "Invalid Name"
            errAlert.informativeText = validationError
            errAlert.alertStyle = .warning
            errAlert.runModal()
            return
        }

        // If editing a reference file, save to the ref file instead
        if let refFile = editingRefFile {
            let refsDir = (skill.skillDir as NSString).appendingPathComponent("references")
            let refPath = (refsDir as NSString).appendingPathComponent(refFile)
            do {
                try editorTextView.string.write(toFile: refPath, atomically: true, encoding: .utf8)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Failed to Save"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
            return
        }

        let content = Self.serializeSkill(
            name: newName,
            description: descField.stringValue,
            userInvocable: invocableCheckbox.state == .on,
            body: editorTextView.string
        )

        // Handle directory rename if name changed
        let skillsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/skills")
        let newDir = (skillsDir as NSString).appendingPathComponent(newName)

        if newName != skill.name && skill.skillDir != newDir {
            if fm.fileExists(atPath: newDir) {
                let errAlert = NSAlert()
                errAlert.messageText = "Skill Already Exists"
                errAlert.informativeText = "A skill named \"\(newName)\" already exists."
                errAlert.alertStyle = .warning
                errAlert.runModal()
                return
            }
            do {
                try fm.moveItem(atPath: skill.skillDir, toPath: newDir)
                let newPath = (newDir as NSString).appendingPathComponent("SKILL.md")
                try content.write(toFile: newPath, atomically: true, encoding: .utf8)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Failed to Rename"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
                return
            }
        } else {
            do {
                try content.write(toFile: skill.path, atomically: true, encoding: .utf8)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Failed to Save"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
                return
            }
        }

        configure()
        // Re-select by name
        if let newIdx = skills.firstIndex(where: { $0.name == newName }) {
            selectedIndex = newIdx
            tableView.selectRowIndexes(IndexSet(integer: newIdx), byExtendingSelection: false)
            loadSkillDetail(at: newIdx)
        }
    }

    @objc private func deleteClicked() {
        guard let idx = selectedIndex, idx < skills.count else { return }
        let skill = skills[idx]

        let alert = NSAlert()
        alert.messageText = "Delete \"\(skill.name)\"?"
        alert.informativeText = "This will permanently delete the skill directory and all its files."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try FileManager.default.removeItem(atPath: skill.skillDir)
            skills.remove(at: idx)
            headerLabel.stringValue = "Skills (\(skills.count))"
            selectedIndex = nil
            clearDetailForm()
            tableView.reloadData()
            emptyLabel.isHidden = !skills.isEmpty
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Failed to Delete"
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .warning
            errAlert.runModal()
        }
    }

    @objc private func newSkillClicked() {
        let alert = NSAlert()
        alert.messageText = "New Skill"
        alert.informativeText = ""
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 42))

        let label = NSTextField(labelWithString: "Name:")
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 0, y: 24, width: 260, height: 16)
        accessory.addSubview(label)

        let nameInput = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        nameInput.placeholderString = "skill-name"
        accessory.addSubview(nameInput)

        alert.accessoryView = accessory
        alert.window.initialFirstResponder = nameInput

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = nameInput.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        if let validationError = Self.validateFilename(name) {
            let errAlert = NSAlert()
            errAlert.messageText = "Invalid Name"
            errAlert.informativeText = validationError
            errAlert.alertStyle = .warning
            errAlert.runModal()
            return
        }

        let skillsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/skills")
        let skillDir = (skillsDir as NSString).appendingPathComponent(name)
        let fm = FileManager.default

        if fm.fileExists(atPath: skillDir) {
            let errAlert = NSAlert()
            errAlert.messageText = "Skill Already Exists"
            errAlert.informativeText = "A skill named \"\(name)\" already exists."
            errAlert.alertStyle = .warning
            errAlert.runModal()
            return
        }

        do {
            try fm.createDirectory(atPath: skillDir, withIntermediateDirectories: true)
            let skeleton = Self.serializeSkill(name: name, description: "", userInvocable: false, body: "")
            let path = (skillDir as NSString).appendingPathComponent("SKILL.md")
            try skeleton.write(toFile: path, atomically: true, encoding: .utf8)
            configure()
            if let idx = skills.firstIndex(where: { $0.name == name }) {
                tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
                loadSkillDetail(at: idx)
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

    @objc private func importClicked() {
        let projects = OpenProjects.shared.projects

        let alert = NSAlert()
        alert.messageText = "Import as Skill"
        alert.informativeText = ""
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 160))
        var y: CGFloat = 160

        // Type label + popup
        y -= 16
        let typeLabel = NSTextField(labelWithString: "Type:")
        typeLabel.font = .systemFont(ofSize: 11, weight: .medium)
        typeLabel.textColor = .secondaryLabelColor
        typeLabel.frame = NSRect(x: 0, y: y, width: 300, height: 16)
        accessory.addSubview(typeLabel)
        y -= 26
        let typePopup = NSPopUpButton(frame: NSRect(x: 0, y: y, width: 300, height: 24), pullsDown: false)
        typePopup.addItem(withTitle: "Prompt")
        typePopup.addItem(withTitle: "Swarm")
        accessory.addSubview(typePopup)
        y -= 8

        // Item label + popup
        y -= 16
        let itemLabel = NSTextField(labelWithString: "Item:")
        itemLabel.font = .systemFont(ofSize: 11, weight: .medium)
        itemLabel.textColor = .secondaryLabelColor
        itemLabel.frame = NSRect(x: 0, y: y, width: 300, height: 16)
        accessory.addSubview(itemLabel)
        y -= 26
        let itemPopup = NSPopUpButton(frame: NSRect(x: 0, y: y, width: 300, height: 24), pullsDown: false)
        accessory.addSubview(itemPopup)
        y -= 8

        // Name label + field
        y -= 16
        let nameLabel = NSTextField(labelWithString: "Skill Name:")
        nameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.frame = NSRect(x: 0, y: y, width: 300, height: 16)
        accessory.addSubview(nameLabel)
        y -= 26
        let nameInput = NSTextField(frame: NSRect(x: 0, y: y, width: 300, height: 24))
        nameInput.placeholderString = "skill-name"
        accessory.addSubview(nameInput)

        // Populate items based on type
        importPrompts = PromptsView.scanPrompts(projects: projects)
        importSwarms = SwarmsView.scanSwarms(projects: projects)
        importTypePopup = typePopup
        importItemPopup = itemPopup
        importNameInput = nameInput

        repopulateImportItems()

        typePopup.target = self
        typePopup.action = #selector(importTypeChanged(_:))

        alert.accessoryView = accessory
        alert.window.initialFirstResponder = nameInput

        guard alert.runModal() == .alertFirstButtonReturn else {
            importTypePopup = nil; importItemPopup = nil; importNameInput = nil
            return
        }
        let name = nameInput.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            importTypePopup = nil; importItemPopup = nil; importNameInput = nil
            return
        }

        if let validationError = Self.validateFilename(name) {
            importTypePopup = nil; importItemPopup = nil; importNameInput = nil
            let errAlert = NSAlert()
            errAlert.messageText = "Invalid Name"
            errAlert.informativeText = validationError
            errAlert.alertStyle = .warning
            errAlert.runModal()
            return
        }

        let isPrompt = typePopup.indexOfSelectedItem == 0
        let itemIdx = itemPopup.indexOfSelectedItem
        guard itemIdx >= 0 else {
            importTypePopup = nil; importItemPopup = nil; importNameInput = nil
            return
        }

        var body = ""
        var description = ""

        if isPrompt && itemIdx < importPrompts.count {
            let prompt = importPrompts[itemIdx]
            let content = (try? String(contentsOfFile: prompt.path, encoding: .utf8)) ?? ""
            body = content
            description = "Imported from prompt: \(prompt.name)"
        } else if !isPrompt && itemIdx < importSwarms.count {
            let swarm = importSwarms[itemIdx]
            description = "Imported from swarm: \(swarm.name)"
            body = """
            Use ppg to orchestrate this task:

            Swarm: \(swarm.name)
            Strategy: \(swarm.strategy)
            Agents: \(swarm.agentCount)

            Run: ppg spawn --swarm \(swarm.name)
            """
        }

        importTypePopup = nil; importItemPopup = nil; importNameInput = nil

        let skillsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/skills")
        let skillDir = (skillsDir as NSString).appendingPathComponent(name)
        let fm = FileManager.default

        if fm.fileExists(atPath: skillDir) {
            let errAlert = NSAlert()
            errAlert.messageText = "Skill Already Exists"
            errAlert.informativeText = "A skill named \"\(name)\" already exists."
            errAlert.alertStyle = .warning
            errAlert.runModal()
            return
        }

        do {
            try fm.createDirectory(atPath: skillDir, withIntermediateDirectories: true)
            let skeleton = Self.serializeSkill(name: name, description: description, userInvocable: false, body: body)
            let path = (skillDir as NSString).appendingPathComponent("SKILL.md")
            try skeleton.write(toFile: path, atomically: true, encoding: .utf8)
            configure()
            if let idx = skills.firstIndex(where: { $0.name == name }) {
                tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
                loadSkillDetail(at: idx)
                selectedIndex = idx
            }
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Failed to Import"
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .warning
            errAlert.runModal()
        }
    }

    @objc private func importTypeChanged(_ sender: NSPopUpButton) {
        repopulateImportItems()
    }

    private func repopulateImportItems() {
        guard let itemPopup = importItemPopup, let typePopup = importTypePopup, let nameInput = importNameInput else { return }
        itemPopup.removeAllItems()
        if typePopup.indexOfSelectedItem == 0 {
            for p in importPrompts { itemPopup.addItem(withTitle: "\(p.projectName)/\(p.name)") }
            if let first = importPrompts.first { nameInput.stringValue = first.name }
        } else {
            for s in importSwarms { itemPopup.addItem(withTitle: "\(s.projectName)/\(s.name)") }
            if let first = importSwarms.first { nameInput.stringValue = first.name }
        }
    }

    // MARK: - Reference File Actions

    @objc private func addRefClicked() {
        guard let idx = selectedIndex, idx < skills.count else { return }
        let skill = skills[idx]

        let alert = NSAlert()
        alert.messageText = "New Reference File"
        alert.informativeText = ""
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 42))

        let label = NSTextField(labelWithString: "Filename:")
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 0, y: 24, width: 260, height: 16)
        accessory.addSubview(label)

        let nameInput = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        nameInput.placeholderString = "reference.md"
        accessory.addSubview(nameInput)

        alert.accessoryView = accessory
        alert.window.initialFirstResponder = nameInput

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var filename = nameInput.stringValue.trimmingCharacters(in: .whitespaces)
        guard !filename.isEmpty else { return }
        if !filename.hasSuffix(".md") { filename += ".md" }

        if let validationError = Self.validateFilename(filename) {
            let errAlert = NSAlert()
            errAlert.messageText = "Invalid Filename"
            errAlert.informativeText = validationError
            errAlert.alertStyle = .warning
            errAlert.runModal()
            return
        }

        let refsDir = (skill.skillDir as NSString).appendingPathComponent("references")
        let fm = FileManager.default

        do {
            if !fm.fileExists(atPath: refsDir) {
                try fm.createDirectory(atPath: refsDir, withIntermediateDirectories: true)
            }
            let refPath = (refsDir as NSString).appendingPathComponent(filename)
            if fm.fileExists(atPath: refPath) {
                let errAlert = NSAlert()
                errAlert.messageText = "File Already Exists"
                errAlert.informativeText = "A reference file named \"\(filename)\" already exists."
                errAlert.alertStyle = .warning
                errAlert.runModal()
                return
            }
            try "".write(toFile: refPath, atomically: true, encoding: .utf8)
            configure()
            // Re-select the skill
            if let newIdx = skills.firstIndex(where: { $0.name == skill.name }) {
                selectedIndex = newIdx
                tableView.selectRowIndexes(IndexSet(integer: newIdx), byExtendingSelection: false)
                loadSkillDetail(at: newIdx)
            }
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Failed to Create"
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .warning
            errAlert.runModal()
        }
    }

    @objc private func removeRefClicked() {
        guard let idx = selectedIndex, idx < skills.count else { return }
        let skill = skills[idx]
        let refRow = refsTableView.selectedRow
        guard refRow >= 0, refRow < skill.referenceFiles.count else { return }
        let refName = skill.referenceFiles[refRow]

        let alert = NSAlert()
        alert.messageText = "Delete \"\(refName)\"?"
        alert.informativeText = "This will permanently delete the reference file."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let refsDir = (skill.skillDir as NSString).appendingPathComponent("references")
        let refPath = (refsDir as NSString).appendingPathComponent(refName)

        do {
            try FileManager.default.removeItem(atPath: refPath)
            // If we were editing this ref file, go back to SKILL.md
            if editingRefFile == refName {
                editingRefFile = nil
                backButton.isHidden = true
                editorTextView.string = skill.body
            }
            configure()
            if let newIdx = skills.firstIndex(where: { $0.name == skill.name }) {
                selectedIndex = newIdx
                tableView.selectRowIndexes(IndexSet(integer: newIdx), byExtendingSelection: false)
                loadSkillDetail(at: newIdx)
            }
        } catch {
            let errAlert = NSAlert()
            errAlert.messageText = "Failed to Delete"
            errAlert.informativeText = error.localizedDescription
            errAlert.alertStyle = .warning
            errAlert.runModal()
        }
    }

    @objc private func refDoubleClicked() {
        guard let idx = selectedIndex, idx < skills.count else { return }
        let skill = skills[idx]
        let refRow = refsTableView.clickedRow
        guard refRow >= 0, refRow < skill.referenceFiles.count else { return }
        let refName = skill.referenceFiles[refRow]
        let refsDir = (skill.skillDir as NSString).appendingPathComponent("references")
        let refPath = (refsDir as NSString).appendingPathComponent(refName)

        guard let content = try? String(contentsOfFile: refPath, encoding: .utf8) else { return }
        // Preserve current editor content (may be unsaved body edits)
        if editingRefFile == nil {
            pendingBodyText = editorTextView.string
        }
        editingRefFile = refName
        backButton.isHidden = false
        editorTextView.string = content
    }

    @objc private func backToSkillClicked() {
        guard let idx = selectedIndex, idx < skills.count else { return }
        editingRefFile = nil
        backButton.isHidden = true
        editorTextView.string = pendingBodyText ?? skills[idx].body
        pendingBodyText = nil
    }
}
