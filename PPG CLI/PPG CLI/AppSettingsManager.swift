import AppKit

extension Notification.Name {
    static let appSettingsDidChange = Notification.Name("PPGAppSettingsDidChange")
}

enum AppSettingsKey: String {
    case agentCommand, refreshInterval
    case terminalFont, terminalFontSize, shell, historyLimit
}

final class AppSettingsManager {
    static let shared = AppSettingsManager()

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key {
        static let agentCommand = "PPGAgentCommand"
        static let refreshInterval = "PPGRefreshInterval"
        static let terminalFont = "PPGTerminalFont"
        static let terminalFontSize = "PPGTerminalFontSize"
        static let shell = "PPGShell"
        static let historyLimit = "PPGHistoryLimit"
    }

    // MARK: - Defaults

    static let defaultAgentCommand = "claude --dangerously-skip-permissions"
    static let defaultRefreshInterval: Double = 2.0
    static let defaultTerminalFont = "Menlo"
    static let defaultTerminalFontSize: CGFloat = 13.0
    static let defaultShell = "/bin/zsh"
    static let defaultHistoryLimit = 50000

    private init() {}

    // MARK: - Properties

    var agentCommand: String {
        get { defaults.string(forKey: Key.agentCommand) ?? Self.defaultAgentCommand }
        set { defaults.set(newValue, forKey: Key.agentCommand); notify(.agentCommand) }
    }

    var refreshInterval: Double {
        get {
            let val = defaults.double(forKey: Key.refreshInterval)
            return val > 0 ? val : Self.defaultRefreshInterval
        }
        set { defaults.set(newValue, forKey: Key.refreshInterval); notify(.refreshInterval) }
    }

    var terminalFontName: String {
        get { defaults.string(forKey: Key.terminalFont) ?? Self.defaultTerminalFont }
        set { defaults.set(newValue, forKey: Key.terminalFont); notify(.terminalFont) }
    }

    var terminalFontSize: CGFloat {
        get {
            let val = defaults.double(forKey: Key.terminalFontSize)
            return val > 0 ? CGFloat(val) : Self.defaultTerminalFontSize
        }
        set { defaults.set(Double(newValue), forKey: Key.terminalFontSize); notify(.terminalFontSize) }
    }

    var shell: String {
        get { defaults.string(forKey: Key.shell) ?? Self.defaultShell }
        set { defaults.set(newValue, forKey: Key.shell); notify(.shell) }
    }

    var historyLimit: Int {
        get {
            let val = defaults.integer(forKey: Key.historyLimit)
            return val > 0 ? val : Self.defaultHistoryLimit
        }
        set { defaults.set(newValue, forKey: Key.historyLimit); notify(.historyLimit) }
    }

    // MARK: - Notification

    static let changedKeyUserInfoKey = "PPGChangedSettingsKey"

    private func notify(_ key: AppSettingsKey) {
        NotificationCenter.default.post(
            name: .appSettingsDidChange,
            object: nil,
            userInfo: [Self.changedKeyUserInfoKey: key]
        )
    }
}
