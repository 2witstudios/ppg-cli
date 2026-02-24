import AppKit

/// Onboarding screen shown when ppg CLI or tmux is not detected.
/// Guides the user through installing the required dependencies.
class SetupViewController: NSViewController {
    var onReady: (() -> Void)?

    private var ppgStatus: StatusRow!
    private var tmuxStatus: StatusRow!
    private var continueButton: NSButton!

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.backgroundColor = chromeBackground.cgColor

        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        // Icon
        let iconView = NSImageView()
        if let image = NSImage(systemSymbolName: "checkmark.shield.fill", accessibilityDescription: "Setup") {
            let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .light)
            iconView.image = image.withSymbolConfiguration(config)
            iconView.contentTintColor = .controlAccentColor
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(iconView)

        // Title
        let titleLabel = NSTextField(labelWithString: "Setup Required")
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "The dashboard needs ppg CLI and tmux to function")
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = .tertiaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(subtitleLabel)

        // Status rows
        ppgStatus = StatusRow(
            title: "ppg CLI",
            installHint: "npm install -g ppg-cli"
        )
        ppgStatus.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(ppgStatus)

        tmuxStatus = StatusRow(
            title: "tmux",
            installHint: "brew install tmux"
        )
        tmuxStatus.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(tmuxStatus)

        // Buttons
        let recheckButton = NSButton(title: "Re-check", target: self, action: #selector(recheckClicked(_:)))
        recheckButton.bezelStyle = .rounded
        recheckButton.controlSize = .large
        recheckButton.translatesAutoresizingMaskIntoConstraints = false

        continueButton = NSButton(title: "Continue", target: self, action: #selector(continueClicked(_:)))
        continueButton.bezelStyle = .rounded
        continueButton.controlSize = .large
        continueButton.keyEquivalent = "\r"
        continueButton.isEnabled = false
        continueButton.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = NSStackView(views: [recheckButton, NSView(), continueButton])
        buttonStack.orientation = .horizontal
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(buttonStack)

        let cardWidth: CGFloat = 480

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            card.widthAnchor.constraint(equalToConstant: cardWidth),

            iconView.topAnchor.constraint(equalTo: card.topAnchor),
            iconView.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            titleLabel.widthAnchor.constraint(equalTo: card.widthAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            subtitleLabel.widthAnchor.constraint(equalTo: card.widthAnchor),

            ppgStatus.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 32),
            ppgStatus.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            ppgStatus.trailingAnchor.constraint(equalTo: card.trailingAnchor),

            tmuxStatus.topAnchor.constraint(equalTo: ppgStatus.bottomAnchor, constant: 12),
            tmuxStatus.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            tmuxStatus.trailingAnchor.constraint(equalTo: card.trailingAnchor),

            buttonStack.topAnchor.constraint(equalTo: tmuxStatus.bottomAnchor, constant: 32),
            buttonStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            buttonStack.heightAnchor.constraint(equalToConstant: 32),
        ])

        runChecks()
    }

    private func runChecks() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let cli = PPGService.shared.checkCLIAvailable()
            let tmux = PPGService.shared.checkTmuxAvailable()

            DispatchQueue.main.async {
                self?.ppgStatus.setStatus(
                    installed: cli.available,
                    detail: cli.version
                )
                self?.tmuxStatus.setStatus(
                    installed: tmux,
                    detail: nil
                )
                self?.continueButton.isEnabled = cli.available && tmux
            }
        }
    }

    @objc private func recheckClicked(_ sender: Any) {
        ppgStatus.setChecking()
        tmuxStatus.setChecking()
        continueButton.isEnabled = false
        runChecks()
    }

    @objc private func continueClicked(_ sender: Any) {
        onReady?()
    }
}

// MARK: - StatusRow

private class StatusRow: NSView {
    private let statusIcon = NSImageView()
    private let titleField: NSTextField
    private let detailField = NSTextField(labelWithString: "")
    private let hintField: NSTextField

    init(title: String, installHint: String) {
        titleField = NSTextField(labelWithString: title)
        hintField = NSTextField(labelWithString: installHint)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusIcon)

        titleField.font = .systemFont(ofSize: 14, weight: .medium)
        titleField.textColor = .labelColor
        titleField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleField)

        detailField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detailField.textColor = .tertiaryLabelColor
        detailField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(detailField)

        hintField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        hintField.textColor = .secondaryLabelColor
        hintField.isSelectable = true
        hintField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintField)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 56),

            statusIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            statusIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusIcon.widthAnchor.constraint(equalToConstant: 20),
            statusIcon.heightAnchor.constraint(equalToConstant: 20),

            titleField.leadingAnchor.constraint(equalTo: statusIcon.trailingAnchor, constant: 12),
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            detailField.leadingAnchor.constraint(equalTo: titleField.trailingAnchor, constant: 8),
            detailField.centerYAnchor.constraint(equalTo: titleField.centerYAnchor),

            hintField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            hintField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
        ])

        setChecking()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setChecking() {
        statusIcon.image = NSImage(systemSymbolName: "circle.dashed", accessibilityDescription: "Checking")
        statusIcon.contentTintColor = .tertiaryLabelColor
        detailField.stringValue = "Checking…"
        hintField.isHidden = true
    }

    func setStatus(installed: Bool, detail: String?) {
        if installed {
            statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Installed")
            statusIcon.contentTintColor = .systemGreen
            detailField.stringValue = detail ?? "Installed"
            hintField.isHidden = true
        } else {
            statusIcon.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Not found")
            statusIcon.contentTintColor = .systemRed
            detailField.stringValue = "Not found"
            hintField.isHidden = false
        }
    }
}
