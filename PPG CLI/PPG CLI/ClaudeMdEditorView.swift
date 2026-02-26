import AppKit

// MARK: - ClaudeMdEditorView

class ClaudeMdEditorView: NSView, NSTextStorageDelegate {

    private let fileSwitcher = NSPopUpButton()
    private let saveButton = NSButton()
    private let editorScrollView = NSScrollView()
    private let editorTextView = NSTextView()
    private var isDirty = false
    private var currentFileIndex: Int = -1
    private var projects: [ProjectContext] = []

    /// Each entry: (display title, file path)
    private var fileEntries: [(String, String)] = []

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
        populateFileSwitcher()
        if let firstRealIdx = fileEntries.firstIndex(where: { $0.0 != "---" }) {
            fileSwitcher.selectItem(at: firstRealIdx)
            loadFile(at: firstRealIdx)
        }
    }

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = Theme.contentBackground.resolvedCGColor(for: effectiveAppearance)

        // Top bar
        let topBar = NSView()
        topBar.translatesAutoresizingMaskIntoConstraints = false

        fileSwitcher.pullsDown = false
        fileSwitcher.font = .systemFont(ofSize: 12)
        fileSwitcher.target = self
        fileSwitcher.action = #selector(fileSwitcherChanged(_:))
        fileSwitcher.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(fileSwitcher)

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
        topBar.addSubview(saveButton)

        let topSep = NSBox()
        topSep.boxType = .separator
        topSep.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(topSep)

        addSubview(topBar)

        // Editor
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
        addSubview(editorScrollView)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: topAnchor),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 36),

            fileSwitcher.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 8),
            fileSwitcher.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            fileSwitcher.widthAnchor.constraint(lessThanOrEqualToConstant: 350),

            saveButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -8),
            saveButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            topSep.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            topSep.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            topSep.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),

            editorScrollView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            editorScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            editorScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            editorScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.contentBackground.resolvedCGColor(for: effectiveAppearance)
        editorTextView.backgroundColor = Theme.contentBackground
        editorScrollView.backgroundColor = Theme.contentBackground
    }

    // MARK: - File Switcher

    private func populateFileSwitcher() {
        fileSwitcher.removeAllItems()
        fileEntries = []
        let fm = FileManager.default
        let prefix = projects.count > 1

        for ctx in projects {
            let root = ctx.projectRoot as NSString
            let pName = ctx.projectName

            // ./CLAUDE.md (primary project instructions)
            let claudeMd = root.appendingPathComponent("CLAUDE.md")
            let claudeMdLabel = prefix ? "\(pName): CLAUDE.md" : "CLAUDE.md"
            fileEntries.append((claudeMdLabel, claudeMd))

            // .claude/CLAUDE.md (alternative location)
            let dotClaudeMd = root.appendingPathComponent(".claude/CLAUDE.md")
            let dotLabel = prefix ? "\(pName): .claude/CLAUDE.md" : ".claude/CLAUDE.md"
            fileEntries.append((dotLabel, dotClaudeMd))

            // CLAUDE.local.md (personal project-specific, gitignored)
            let localMd = root.appendingPathComponent("CLAUDE.local.md")
            let localLabel = prefix ? "\(pName): CLAUDE.local.md" : "CLAUDE.local.md"
            fileEntries.append((localLabel, localMd))

            // .claude/rules/*.md (modular project rules)
            let rulesDir = root.appendingPathComponent(".claude/rules")
            if let ruleFiles = try? fm.contentsOfDirectory(atPath: rulesDir) {
                for file in ruleFiles.sorted() where file.hasSuffix(".md") {
                    let rulePath = (rulesDir as NSString).appendingPathComponent(file)
                    let ruleLabel = prefix ? "\(pName): .claude/rules/\(file)" : ".claude/rules/\(file)"
                    fileEntries.append((ruleLabel, rulePath))
                }
            }
        }

        // Separator
        fileEntries.append(("---", ""))

        // User: ~/.claude/CLAUDE.md
        let userPath = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/CLAUDE.md")
        fileEntries.append(("User: ~/.claude/CLAUDE.md", userPath))

        // User: ~/.claude/rules/*.md
        let userRulesDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/rules")
        if let userRuleFiles = try? fm.contentsOfDirectory(atPath: userRulesDir) {
            for file in userRuleFiles.sorted() where file.hasSuffix(".md") {
                let rulePath = (userRulesDir as NSString).appendingPathComponent(file)
                fileEntries.append(("User: ~/.claude/rules/\(file)", rulePath))
            }
        }

        for (title, _) in fileEntries {
            if title == "---" {
                fileSwitcher.menu?.addItem(NSMenuItem.separator())
            } else {
                fileSwitcher.addItem(withTitle: title)
            }
        }
    }

    private func loadFile(at index: Int) {
        guard index >= 0, index < fileEntries.count else { return }
        let (title, path) = fileEntries[index]
        guard title != "---", !path.isEmpty else { return }
        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        editorTextView.string = content
        currentFileIndex = index
        isDirty = false
        saveButton.isEnabled = false
    }

    @objc private func fileSwitcherChanged(_ sender: NSPopUpButton) {
        if isDirty {
            let alert = NSAlert()
            alert.messageText = "Unsaved Changes"
            alert.informativeText = "You have unsaved changes. Discard them?"
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn {
                if currentFileIndex >= 0 {
                    sender.selectItem(at: currentFileIndex)
                }
                return
            }
        }
        loadFile(at: sender.indexOfSelectedItem)
    }

    // MARK: - Save

    @objc private func saveClicked() {
        let index = (currentFileIndex >= 0) ? currentFileIndex : fileSwitcher.indexOfSelectedItem
        guard index >= 0, index < fileEntries.count else { return }
        let path = fileEntries[index].1

        let fm = FileManager.default
        let dir = (path as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        do {
            try editorTextView.string.write(toFile: path, atomically: true, encoding: .utf8)
            isDirty = false
            saveButton.isEnabled = false
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to Save"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: - NSTextStorageDelegate

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        isDirty = true
        saveButton.isEnabled = true
    }
}
