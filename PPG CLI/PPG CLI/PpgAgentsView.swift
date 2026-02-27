import AppKit

// MARK: - PpgAgentsView

class PpgAgentsView: NSView, NSTextStorageDelegate {

    private let projectSwitcher = NSPopUpButton()
    private let saveButton = NSButton()
    private let editorScrollView = NSScrollView()
    private let editorTextView = NSTextView()
    private let emptyLabel = NSTextField(labelWithString: "No .ppg/config.yaml found")
    private var isDirty = false
    private var currentConfigIndex: Int = -1
    private var projects: [ProjectContext] = []

    /// Each entry: (display title, file path)
    private var configEntries: [(String, String)] = []

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
        populateProjectSwitcher()
        if !configEntries.isEmpty {
            projectSwitcher.selectItem(at: 0)
            loadConfig(at: 0)
            emptyLabel.isHidden = true
            editorScrollView.isHidden = false
            projectSwitcher.isHidden = false
        } else {
            editorTextView.string = ""
            emptyLabel.isHidden = false
            editorScrollView.isHidden = true
            projectSwitcher.isHidden = true
            saveButton.isEnabled = false
        }
    }

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = Theme.contentBackground.resolvedCGColor(for: effectiveAppearance)

        // Top bar
        let topBar = NSView()
        topBar.translatesAutoresizingMaskIntoConstraints = false

        projectSwitcher.pullsDown = false
        projectSwitcher.font = .systemFont(ofSize: 12)
        projectSwitcher.target = self
        projectSwitcher.action = #selector(projectSwitcherChanged(_:))
        projectSwitcher.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(projectSwitcher)

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

        // Empty label
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: topAnchor),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 36),

            projectSwitcher.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 8),
            projectSwitcher.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            projectSwitcher.widthAnchor.constraint(lessThanOrEqualToConstant: 350),

            saveButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -8),
            saveButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            topSep.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            topSep.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            topSep.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),

            editorScrollView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            editorScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            editorScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            editorScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.contentBackground.resolvedCGColor(for: effectiveAppearance)
        editorTextView.backgroundColor = Theme.contentBackground
        editorScrollView.backgroundColor = Theme.contentBackground
    }

    // MARK: - Project Switcher

    private func populateProjectSwitcher() {
        projectSwitcher.removeAllItems()
        configEntries = []

        let fm = FileManager.default
        for ctx in projects {
            let path = (ctx.projectRoot as NSString).appendingPathComponent(".ppg/config.yaml")
            if fm.fileExists(atPath: path) {
                let label = projects.count > 1
                    ? "\(ctx.projectName)/.ppg/config.yaml"
                    : ".ppg/config.yaml"
                configEntries.append((label, path))
            }
        }

        for (title, _) in configEntries {
            projectSwitcher.addItem(withTitle: title)
        }
    }

    private func loadConfig(at index: Int) {
        guard index >= 0, index < configEntries.count else { return }
        let path = configEntries[index].1
        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        editorTextView.string = content
        currentConfigIndex = index
        isDirty = false
        saveButton.isEnabled = false
        SyntaxHighlighter.highlightYAML(editorTextView.textStorage)
    }

    @objc private func projectSwitcherChanged(_ sender: NSPopUpButton) {
        if isDirty {
            let alert = NSAlert()
            alert.messageText = "Unsaved Changes"
            alert.informativeText = "You have unsaved changes. Discard them?"
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn {
                if currentConfigIndex >= 0 {
                    sender.selectItem(at: currentConfigIndex)
                }
                return
            }
        }
        loadConfig(at: sender.indexOfSelectedItem)
    }

    // MARK: - Save

    @objc private func saveClicked() {
        let index = (currentConfigIndex >= 0) ? currentConfigIndex : projectSwitcher.indexOfSelectedItem
        guard index >= 0, index < configEntries.count else { return }
        let path = configEntries[index].1

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
        SyntaxHighlighter.highlightYAML(editorTextView.textStorage)
    }
}
