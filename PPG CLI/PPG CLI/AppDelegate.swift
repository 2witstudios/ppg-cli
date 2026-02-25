import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        KeybindingManager.shared.applyBindings(to: NSApp.mainMenu!)

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1400, height: 900)

        window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.backgroundColor = chromeBackground
        window.isOpaque = false
        window.isRestorable = false

        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        // Launch flow: check prerequisites, then restore projects or show picker
        let cli = PPGService.shared.checkCLIAvailable()
        let tmux = PPGService.shared.checkTmuxAvailable()

        if cli.available && tmux {
            proceedToProjects()
            if let version = cli.version {
                checkCLIVersion(installedVersion: version)
            }
        } else {
            showSetup()
        }

        window.setFrame(screenFrame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func proceedToProjects() {
        if !OpenProjects.shared.projects.isEmpty {
            showDashboard()
        } else if let lastProject = RecentProjects.shared.lastOpened,
                  RecentProjects.shared.isValidProject(lastProject) {
            OpenProjects.shared.add(root: lastProject)
            showDashboard()
        } else {
            showProjectPicker()
        }
    }

    private func showSetup() {
        let frame = window.frame
        window.title = "ppg — Setup"
        let setup = SetupViewController()
        setup.onReady = { [weak self] in
            self?.proceedToProjects()
        }
        window.contentViewController = setup
        window.setFrame(frame, display: true)
    }

    private func showDashboard() {
        let frame = window.frame
        let activeProject = OpenProjects.shared.projects.first
        window.title = activeProject.map { $0.projectName } ?? "ppg"
        window.contentViewController = DashboardSplitViewController()
        window.setFrame(frame, display: true)
    }

    private func showProjectPicker() {
        let frame = window.frame
        window.title = "ppg — Select Project"
        let picker = ProjectPickerViewController()
        picker.onProjectSelected = { [weak self] root in
            OpenProjects.shared.add(root: root)
            RecentProjects.shared.add(root)
            self?.showDashboard()
        }
        window.contentViewController = picker
        window.setFrame(frame, display: true)
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        appMenu.addItem(withTitle: "About PPG CLI",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")

        appMenu.addItem(.separator())

        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates...",
            action: nil,
            keyEquivalent: "")
        appMenu.addItem(checkForUpdatesItem)
        UpdaterManager.shared.wireMenuItem(checkForUpdatesItem)

        appMenu.addItem(.separator())

        let quitItem = appMenu.addItem(withTitle: "Quit PPG CLI",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        quitItem.tag = kMenuTagQuit

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")

        // Cmd+N — New... (creation menu)
        let newItem = NSMenuItem(title: "New...", action: #selector(showCreationMenu(_:)), keyEquivalent: "n")
        newItem.target = self
        newItem.tag = kMenuTagNew
        fileMenu.addItem(newItem)

        fileMenu.addItem(.separator())

        // Cmd+O — Open/Add Project
        let openItem = fileMenu.addItem(withTitle: "Open Project...", action: #selector(openProjectAction(_:)), keyEquivalent: "o")
        openItem.target = self
        openItem.tag = kMenuTagOpen

        // Recent Projects submenu (no Cmd+1-9 shortcuts here — those are for project switching)
        let recentItem = NSMenuItem(title: "Recent Projects", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Recent Projects")
        let recentProjects = RecentProjects.shared.projects.filter { RecentProjects.shared.isValidProject($0) }
        if recentProjects.isEmpty {
            let emptyItem = NSMenuItem(title: "No Recent Projects", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            recentMenu.addItem(emptyItem)
        } else {
            for project in recentProjects {
                let name = URL(fileURLWithPath: project).lastPathComponent
                let item = NSMenuItem(title: name, action: #selector(openRecentProject(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = project
                recentMenu.addItem(item)
            }
        }
        recentItem.submenu = recentMenu
        fileMenu.addItem(recentItem)

        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")

        // Cmd+1-9 — switch to project 1-9
        let projectMenuTags = [
            kMenuTagProject1, kMenuTagProject2, kMenuTagProject3,
            kMenuTagProject4, kMenuTagProject5, kMenuTagProject6,
            kMenuTagProject7, kMenuTagProject8, kMenuTagProject9,
        ]
        for i in 1...9 {
            let projectItem = NSMenuItem(title: "Project \(i)", action: #selector(switchToProject(_:)), keyEquivalent: "\(i)")
            projectItem.target = self
            projectItem.tag = projectMenuTags[i - 1]
            projectItem.representedObject = i  // store the project index
            viewMenu.addItem(projectItem)
        }
        viewMenu.addItem(.separator())

        let closeItem = NSMenuItem(title: "Close", action: #selector(closeCurrentEntry), keyEquivalent: "w")
        closeItem.target = self
        closeItem.tag = kMenuTagClose
        viewMenu.addItem(closeItem)

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshSidebar), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.tag = kMenuTagRefresh
        viewMenu.addItem(refreshItem)

        viewMenu.addItem(.separator())

        let splitBelowItem = NSMenuItem(title: "Split Pane Below", action: #selector(splitPaneBelow), keyEquivalent: "d")
        splitBelowItem.target = self
        splitBelowItem.tag = kMenuTagSplitBelow
        viewMenu.addItem(splitBelowItem)

        let splitRightItem = NSMenuItem(title: "Split Pane Right", action: #selector(splitPaneRight), keyEquivalent: "d")
        splitRightItem.keyEquivalentModifierMask = [.command, .shift]
        splitRightItem.target = self
        splitRightItem.tag = kMenuTagSplitRight
        viewMenu.addItem(splitRightItem)

        let closePaneItem = NSMenuItem(title: "Close Pane", action: #selector(closeFocusedPane), keyEquivalent: "w")
        closePaneItem.keyEquivalentModifierMask = [.command, .shift]
        closePaneItem.target = self
        closePaneItem.tag = kMenuTagClosePane
        viewMenu.addItem(closePaneItem)

        viewMenu.addItem(.separator())

        let focusUpItem = NSMenuItem(title: "Focus Pane Above", action: #selector(focusPaneUp), keyEquivalent: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)))
        focusUpItem.keyEquivalentModifierMask = [.command, .option]
        focusUpItem.target = self
        focusUpItem.tag = kMenuTagFocusPaneUp
        viewMenu.addItem(focusUpItem)

        let focusDownItem = NSMenuItem(title: "Focus Pane Below", action: #selector(focusPaneDown), keyEquivalent: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)))
        focusDownItem.keyEquivalentModifierMask = [.command, .option]
        focusDownItem.target = self
        focusDownItem.tag = kMenuTagFocusPaneDown
        viewMenu.addItem(focusDownItem)

        let focusLeftItem = NSMenuItem(title: "Focus Pane Left", action: #selector(focusPaneLeft), keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)))
        focusLeftItem.keyEquivalentModifierMask = [.command, .option]
        focusLeftItem.target = self
        focusLeftItem.tag = kMenuTagFocusPaneLeft
        viewMenu.addItem(focusLeftItem)

        let focusRightItem = NSMenuItem(title: "Focus Pane Right", action: #selector(focusPaneRight), keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)))
        focusRightItem.keyEquivalentModifierMask = [.command, .option]
        focusRightItem.target = self
        focusRightItem.tag = kMenuTagFocusPaneRight
        viewMenu.addItem(focusRightItem)

        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func switchToProject(_ sender: NSMenuItem) {
        guard let splitVC = window?.contentViewController as? DashboardSplitViewController else { return }
        let index = (sender.representedObject as? Int) ?? 1
        splitVC.sidebar.selectProject(at: index - 1)
    }

    @objc private func closeCurrentEntry() {
        guard let splitVC = window?.contentViewController as? DashboardSplitViewController else { return }
        splitVC.closeCurrentEntry()
    }

    @objc private func refreshSidebar() {
        guard let splitVC = window?.contentViewController as? DashboardSplitViewController else { return }
        splitVC.sidebar.refresh()
    }

    @objc private func showCreationMenu(_ sender: Any) {
        guard let splitVC = window?.contentViewController as? DashboardSplitViewController else { return }
        splitVC.showCreationMenu()
    }

    @objc private func splitPaneBelow() {
        guard let splitVC = window?.contentViewController as? DashboardSplitViewController else { return }
        splitVC.splitPaneBelow()
    }

    @objc private func splitPaneRight() {
        guard let splitVC = window?.contentViewController as? DashboardSplitViewController else { return }
        splitVC.splitPaneRight()
    }

    @objc private func closeFocusedPane() {
        guard let splitVC = window?.contentViewController as? DashboardSplitViewController else { return }
        splitVC.closeFocusedPane()
    }

    @objc private func focusPaneUp() {
        guard let splitVC = window?.contentViewController as? DashboardSplitViewController else { return }
        splitVC.movePaneFocus(direction: .horizontal, forward: false)
    }

    @objc private func focusPaneDown() {
        guard let splitVC = window?.contentViewController as? DashboardSplitViewController else { return }
        splitVC.movePaneFocus(direction: .horizontal, forward: true)
    }

    @objc private func focusPaneLeft() {
        guard let splitVC = window?.contentViewController as? DashboardSplitViewController else { return }
        splitVC.movePaneFocus(direction: .vertical, forward: false)
    }

    @objc private func focusPaneRight() {
        guard let splitVC = window?.contentViewController as? DashboardSplitViewController else { return }
        splitVC.movePaneFocus(direction: .vertical, forward: true)
    }

    func openProject() {
        openProjectAction(self)
    }

    @objc private func openProjectAction(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a project directory"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path

        if !RecentProjects.shared.isValidProject(path) {
            // Not initialized — offer to run ppg init
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

        OpenProjects.shared.add(root: path)

        // If we're on the project picker, switch to dashboard; otherwise just refresh sidebar
        if window?.contentViewController is ProjectPickerViewController {
            showDashboard()
        } else if let splitVC = window?.contentViewController as? DashboardSplitViewController {
            splitVC.sidebar.refresh()
            // Update window title to show active project
            if let active = OpenProjects.shared.projects.first {
                window.title = active.projectName
            }
        }
    }

    @objc private func openRecentProject(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        OpenProjects.shared.add(root: path)

        if window?.contentViewController is ProjectPickerViewController {
            showDashboard()
        } else if let splitVC = window?.contentViewController as? DashboardSplitViewController {
            splitVC.sidebar.refresh()
        }
    }

    // MARK: - CLI Version Check

    private static let cliUpdateDismissedKey = "CLIUpdateDismissed"

    private func checkCLIVersion(installedVersion: String) {
        DispatchQueue.global(qos: .utility).async {
            guard let latest = PPGService.shared.checkLatestCLIVersion() else { return }
            guard Self.isVersion(installed: installedVersion, olderThan: latest) else { return }

            let dismissedValue = UserDefaults.standard.string(forKey: Self.cliUpdateDismissedKey)
            let currentKey = "\(installedVersion):\(latest)"
            guard dismissedValue != currentKey else { return }

            DispatchQueue.main.async { [weak self] in
                self?.showCLIUpdateAlert(installed: installedVersion, latest: latest)
            }
        }
    }

    /// Compare two semver strings. Returns true if `installed` is strictly older than `latest`.
    static func isVersion(installed: String, olderThan latest: String) -> Bool {
        let iParts = installed.split(separator: ".").compactMap { Int($0) }
        let lParts = latest.split(separator: ".").compactMap { Int($0) }
        let count = max(iParts.count, lParts.count)
        for i in 0..<count {
            let a = i < iParts.count ? iParts[i] : 0
            let b = i < lParts.count ? lParts[i] : 0
            if a < b { return true }
            if a > b { return false }
        }
        return false
    }

    private func showCLIUpdateAlert(installed: String, latest: String) {
        let alert = NSAlert()
        alert.messageText = "CLI Update Available"
        alert.informativeText = "ppg CLI \(latest) is available (you have \(installed)). Update now?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            runCLIUpdate()
        } else {
            let key = "\(installed):\(latest)"
            UserDefaults.standard.set(key, forKey: Self.cliUpdateDismissedKey)
        }
    }

    private func runCLIUpdate() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = PPGService.shared.updateCLI()
            let newVersion = PPGService.shared.checkCLIAvailable().version

            DispatchQueue.main.async {
                let alert = NSAlert()
                if result.success, let v = newVersion {
                    alert.messageText = "CLI Updated"
                    alert.informativeText = "ppg CLI updated to \(v)."
                    alert.alertStyle = .informational
                    // Clear any stored dismissal since versions changed
                    UserDefaults.standard.removeObject(forKey: Self.cliUpdateDismissedKey)
                } else {
                    alert.messageText = "Update Failed"
                    alert.informativeText = "Could not update ppg CLI.\n\n\(result.output.prefix(500))"
                    alert.alertStyle = .warning
                }
                alert.runModal()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Flush any debounced dashboard session writes before exit
        for project in OpenProjects.shared.projects {
            project.dashboardSession.flushToDisk()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false
    }
}
