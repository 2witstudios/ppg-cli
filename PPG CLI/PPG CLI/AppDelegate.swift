import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    private var projectChangeObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.setFrameAutosaveName("PPGMainWindow")
        window.center()

        // Glass toolbar chrome strip
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        projectChangeObserver = NotificationCenter.default.addObserver(
            forName: .projectDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onProjectChanged()
        }

        if ProjectState.shared.isConfigured {
            showDashboard()
        } else {
            showProjectPicker()
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showDashboard() {
        window.title = "ppg — \(ProjectState.shared.projectName)"
        DashboardSession.shared.reloadFromDisk()
        window.contentViewController = DashboardSplitViewController()
    }

    private func showProjectPicker() {
        window.title = "ppg — Select Project"
        let picker = ProjectPickerViewController()
        picker.onProjectSelected = { [weak self] root in
            ProjectState.shared.switchProject(root: root)
            self?.showDashboard()
        }
        window.contentViewController = picker
    }

    private func onProjectChanged() {
        showDashboard()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit PPG CLI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open Project...", action: #selector(openProjectAction(_:)), keyEquivalent: "o")
            .target = self

        // Recent Projects submenu
        let recentItem = NSMenuItem(title: "Recent Projects", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Recent Projects")
        let recentProjects = RecentProjects.shared.projects.filter { RecentProjects.shared.isValidProject($0) }
        if recentProjects.isEmpty {
            let emptyItem = NSMenuItem(title: "No Recent Projects", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            recentMenu.addItem(emptyItem)
        } else {
            for (index, project) in recentProjects.enumerated() {
                let name = URL(fileURLWithPath: project).lastPathComponent
                let item = NSMenuItem(title: name, action: #selector(openRecentProject(_:)), keyEquivalent: index < 9 ? "\(index + 1)" : "")
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
        for i in 1...9 {
            let tabItem = NSMenuItem(title: "Tab \(i)", action: #selector(switchToTab(_:)), keyEquivalent: "\(i)")
            tabItem.target = self
            tabItem.tag = i
            viewMenu.addItem(tabItem)
        }
        viewMenu.addItem(.separator())
        let closeItem = NSMenuItem(title: "Close Tab", action: #selector(closeCurrentTab), keyEquivalent: "w")
        closeItem.target = self
        viewMenu.addItem(closeItem)
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshSidebar), keyEquivalent: "r")
        refreshItem.target = self
        viewMenu.addItem(refreshItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func switchToTab(_ sender: NSMenuItem) {
        guard let splitVC = window?.contentViewController as? DashboardSplitViewController else { return }
        splitVC.content.selectTab(at: sender.tag - 1)
    }

    @objc private func closeCurrentTab() {
        guard let splitVC = window?.contentViewController as? DashboardSplitViewController else { return }
        let idx = splitVC.content.selectedIndex
        if idx >= 0 {
            splitVC.content.removeTab(at: idx)
        }
    }

    @objc private func refreshSidebar() {
        guard let splitVC = window?.contentViewController as? DashboardSplitViewController else { return }
        splitVC.sidebar.refresh()
    }

    @objc private func openProjectAction(_ sender: Any) {
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

        ProjectState.shared.switchProject(root: path)
    }

    @objc private func openRecentProject(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        ProjectState.shared.switchProject(root: path)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    deinit {
        if let observer = projectChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
