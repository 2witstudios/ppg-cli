import AppKit

class FeedbackViewController: NSViewController {

    private let categoryControl = NSSegmentedControl()
    private let titleField = NSTextField()
    private let bodyScrollView = NSScrollView()
    private let bodyTextView = NSTextView()
    private let submitButton = NSButton()
    private let cancelButton = NSButton()
    private let spinner = NSProgressIndicator()

    private let categories = ["bug", "feature", "feedback"]

    override func loadView() {
        let container = ThemeAwareView(frame: NSRect(x: 0, y: 0, width: 480, height: 380))
        container.onAppearanceChanged = { [weak self] in
            guard let self = self else { return }
            self.applyTheme()
        }
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Submit Feedback"

        applyTheme()

        // Category picker
        categoryControl.segmentCount = 3
        categoryControl.setLabel("Bug", forSegment: 0)
        categoryControl.setLabel("Feature Request", forSegment: 1)
        categoryControl.setLabel("General Feedback", forSegment: 2)
        categoryControl.segmentStyle = .texturedRounded
        categoryControl.selectedSegment = 2
        categoryControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(categoryControl)

        // Title label
        let titleLabel = NSTextField(labelWithString: "Title")
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = Theme.primaryText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // Title field
        titleField.placeholderString = "Brief summary of your feedback"
        titleField.font = .systemFont(ofSize: 13)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleField)

        // Body label
        let bodyLabel = NSTextField(labelWithString: "Details")
        bodyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        bodyLabel.textColor = Theme.primaryText
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bodyLabel)

        // Body text view
        bodyScrollView.hasVerticalScroller = true
        bodyScrollView.borderType = .bezelBorder
        bodyScrollView.translatesAutoresizingMaskIntoConstraints = false

        bodyTextView.isRichText = false
        bodyTextView.font = .systemFont(ofSize: 13)
        bodyTextView.isVerticallyResizable = true
        bodyTextView.isHorizontallyResizable = false
        bodyTextView.textContainer?.widthTracksTextView = true
        bodyTextView.minSize = NSSize(width: 0, height: 0)
        bodyTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        bodyScrollView.documentView = bodyTextView
        view.addSubview(bodyScrollView)

        // Spinner
        spinner.style = .spinning
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        // Cancel button
        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.keyEquivalent = "\u{1b}"  // Escape
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        // Submit button
        submitButton.title = "Submit"
        submitButton.bezelStyle = .rounded
        submitButton.keyEquivalent = "\r"
        submitButton.target = self
        submitButton.action = #selector(submitClicked)
        submitButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(submitButton)

        NSLayoutConstraint.activate([
            categoryControl.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            categoryControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: categoryControl.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            titleField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            titleField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            bodyLabel.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 12),
            bodyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            bodyScrollView.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 4),
            bodyScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            bodyScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            bodyScrollView.heightAnchor.constraint(equalToConstant: 150),

            submitButton.topAnchor.constraint(equalTo: bodyScrollView.bottomAnchor, constant: 16),
            submitButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            submitButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),

            cancelButton.centerYAnchor.constraint(equalTo: submitButton.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: submitButton.leadingAnchor, constant: -8),

            spinner.centerYAnchor.constraint(equalTo: submitButton.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -8),
        ])
    }

    private func applyTheme() {
        view.wantsLayer = true
        view.layer?.backgroundColor = Theme.contentBackground.resolvedCGColor(for: view.effectiveAppearance)
    }

    @objc private func cancelClicked() {
        dismiss(nil)
    }

    @objc private func submitClicked() {
        let titleText = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyText = bodyTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !titleText.isEmpty else {
            shake(titleField)
            return
        }
        guard !bodyText.isEmpty else {
            shake(bodyScrollView)
            return
        }

        let label = categories[categoryControl.selectedSegment]

        submitButton.isEnabled = false
        cancelButton.isEnabled = false
        spinner.startAnimation(nil)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Use the first open project root, or fall back to home directory
            let projectRoot = OpenProjects.shared.projects.first?.projectRoot ?? NSHomeDirectory()
            let args = "feedback --title \(shellEscape(titleText)) --body \(shellEscape(bodyText)) --label \(shellEscape(label)) --json"
            let result = PPGService.shared.runPPGCommand(args, projectRoot: projectRoot)

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.spinner.stopAnimation(nil)
                self.submitButton.isEnabled = true
                self.cancelButton.isEnabled = true

                if result.exitCode == 0 {
                    self.showSuccessAndDismiss()
                } else {
                    let msg = result.stderr.isEmpty ? result.stdout : result.stderr
                    let alert = NSAlert()
                    alert.messageText = "Failed to submit feedback"
                    alert.informativeText = msg.trimmingCharacters(in: .whitespacesAndNewlines)
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    private func showSuccessAndDismiss() {
        let alert = NSAlert()
        alert.messageText = "Feedback submitted"
        alert.informativeText = "Thank you for your feedback!"
        alert.alertStyle = .informational
        alert.beginSheetModal(for: view.window!) { [weak self] _ in
            self?.dismiss(nil)
        }
    }

    private func shake(_ view: NSView) {
        let animation = CAKeyframeAnimation(keyPath: "position.x")
        animation.values = [0, -6, 6, -4, 4, -2, 2, 0].map { view.frame.midX + $0 }
        animation.duration = 0.4
        animation.calculationMode = .linear
        view.layer?.add(animation, forKey: "shake")
    }
}
