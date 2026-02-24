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
        window.appearance = NSAppearance(named: .darkAqua)

        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        // Launch flow: restore persisted open projects, or fall back to last opened, or show picker
        if !OpenProjects.shared.projects.isEmpty {
            showDashboard()
        } else if let lastProject = RecentProjects.shared.lastOpened,
                  RecentProjects.shared.isValidProject(lastProject) {
            OpenProjects.shared.add(root: lastProject)
            showDashboard()
        } else {
            showProjectPicker()
        }

        window.setFrame(screenFrame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        let quitItem = appMenu.addItem(withTitle: "Quit PPG CLI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

    func openProject() {
        openProjectAction(self)
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false
    }
}
