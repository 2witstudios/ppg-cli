import AppKit

extension Notification.Name {
    static let appSettingsDidChange = Notification.Name("PPGAppSettingsDidChange")
}

enum AppSettingsKey: String {
    case refreshInterval
    case terminalFont, terminalFontSize, shell, historyLimit
    case appearanceMode
}

enum AppearanceMode: String {
    case system, light, dark

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

final class AppSettingsManager {
    static let shared = AppSettingsManager()

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key {
        static let refreshInterval = "PPGRefreshInterval"
        static let terminalFont = "PPGTerminalFont"
        static let terminalFontSize = "PPGTerminalFontSize"
        static let shell = "PPGShell"
        static let historyLimit = "PPGHistoryLimit"
        static let appearanceMode = "PPGAppearanceMode"
    }

    // MARK: - Defaults

    static let defaultRefreshInterval: Double = 2.0
    static let defaultTerminalFont = "Menlo"
    static let defaultTerminalFontSize: CGFloat = 13.0
    static let defaultShell = "/bin/zsh"
    static let defaultHistoryLimit = 50000

    private init() {}

    // MARK: - Properties

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

    var appearanceMode: AppearanceMode {
        get {
            guard let raw = defaults.string(forKey: Key.appearanceMode) else { return .system }
            return AppearanceMode(rawValue: raw) ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.appearanceMode)
            applyAppearance(newValue)
            notify(.appearanceMode)
        }
    }

    func applyAppearance(_ mode: AppearanceMode? = nil) {
        let resolved = (mode ?? appearanceMode).nsAppearance
        NSApp.appearance = resolved
        for window in NSApp.windows {
            window.appearance = resolved
            if window.backgroundColor.alphaComponent == 0 {
                window.backgroundColor = .clear
            } else if window.isOpaque {
                window.backgroundColor = Theme.contentBackground
            } else {
                window.backgroundColor = Theme.chromeBackground
            }
            window.invalidateShadow()
            window.display()  // force full redraw — liquid glass re-samples content
        }
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
