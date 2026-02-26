import AppKit

// MARK: - AgentConfigView

class AgentConfigView: NSView {

    private let segmentedControl = NSSegmentedControl()
    private var childViews: [NSView] = []
    private var activeChildIndex: Int = 0
    private var projects: [ProjectContext] = []

    // Lazy child views
    private lazy var claudeMdEditor = ClaudeMdEditorView()
    private lazy var skillsView = SkillsView()
    private lazy var ppgAgentsView = PpgAgentsView()

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
        // Forward to active child
        switch activeChildIndex {
        case 0: claudeMdEditor.configure(projects: projects)
        case 1: skillsView.configure(projects: projects)
        case 2: ppgAgentsView.configure(projects: projects)
        default: break
        }
    }

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = Theme.contentBackground.resolvedCGColor(for: effectiveAppearance)

        // Segment bar
        let segmentBar = NSView()
        segmentBar.translatesAutoresizingMaskIntoConstraints = false

        segmentedControl.segmentCount = 3
        segmentedControl.setLabel("CLAUDE.md", forSegment: 0)
        segmentedControl.setLabel("Skills", forSegment: 1)
        segmentedControl.setLabel("Agents", forSegment: 2)
        segmentedControl.segmentStyle = .texturedRounded
        segmentedControl.selectedSegment = 0
        segmentedControl.target = self
        segmentedControl.action = #selector(segmentChanged(_:))
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentBar.addSubview(segmentedControl)

        let segSep = NSBox()
        segSep.boxType = .separator
        segSep.translatesAutoresizingMaskIntoConstraints = false
        segmentBar.addSubview(segSep)

        addSubview(segmentBar)

        NSLayoutConstraint.activate([
            segmentBar.topAnchor.constraint(equalTo: topAnchor),
            segmentBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            segmentBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            segmentBar.heightAnchor.constraint(equalToConstant: 36),

            segmentedControl.centerXAnchor.constraint(equalTo: segmentBar.centerXAnchor),
            segmentedControl.centerYAnchor.constraint(equalTo: segmentBar.centerYAnchor),

            segSep.bottomAnchor.constraint(equalTo: segmentBar.bottomAnchor),
            segSep.leadingAnchor.constraint(equalTo: segmentBar.leadingAnchor),
            segSep.trailingAnchor.constraint(equalTo: segmentBar.trailingAnchor),
        ])

        childViews = [claudeMdEditor, skillsView, ppgAgentsView]

        // Show initial child
        showChild(at: 0, below: segmentBar)
    }

    private func showChild(at index: Int, below segmentBar: NSView? = nil) {
        // Remove current child
        for child in childViews where child.superview === self {
            child.removeFromSuperview()
        }

        let child = childViews[index]
        child.translatesAutoresizingMaskIntoConstraints = false
        addSubview(child)

        let topView = segmentBar ?? subviews.first { $0 is NSView && $0 != child }
        let topAnchorRef: NSLayoutYAxisAnchor
        if let bar = topView, bar !== child {
            topAnchorRef = bar.bottomAnchor
        } else {
            topAnchorRef = topAnchor
        }

        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: topAnchorRef),
            child.leadingAnchor.constraint(equalTo: leadingAnchor),
            child.trailingAnchor.constraint(equalTo: trailingAnchor),
            child.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        activeChildIndex = index

        // Configure the newly shown child
        switch index {
        case 0: claudeMdEditor.configure(projects: projects)
        case 1: skillsView.configure(projects: projects)
        case 2: ppgAgentsView.configure(projects: projects)
        default: break
        }
    }

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        let idx = sender.selectedSegment
        guard idx != activeChildIndex else { return }
        // The segment bar is always the first subview
        let segmentBar = subviews.first { $0 !== childViews[activeChildIndex] }
        showChild(at: idx, below: segmentBar)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.contentBackground.resolvedCGColor(for: effectiveAppearance)
    }
}
