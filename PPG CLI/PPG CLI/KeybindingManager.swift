import AppKit

// MARK: - Bindable Action

enum BindableAction: String, CaseIterable {
    case quit
    case newItem
    case openProject
    case switchProject1
    case switchProject2
    case switchProject3
    case switchProject4
    case switchProject5
    case switchProject6
    case switchProject7
    case switchProject8
    case switchProject9
    case closeEntry
    case refresh

    var displayName: String {
        switch self {
        case .quit: return "Quit"
        case .newItem: return "New..."
        case .openProject: return "Open Project"
        case .switchProject1: return "Switch to Project 1"
        case .switchProject2: return "Switch to Project 2"
        case .switchProject3: return "Switch to Project 3"
        case .switchProject4: return "Switch to Project 4"
        case .switchProject5: return "Switch to Project 5"
        case .switchProject6: return "Switch to Project 6"
        case .switchProject7: return "Switch to Project 7"
        case .switchProject8: return "Switch to Project 8"
        case .switchProject9: return "Switch to Project 9"
        case .closeEntry: return "Close"
        case .refresh: return "Refresh"
        }
    }

    var defaultKeyEquivalent: String {
        switch self {
        case .quit: return "q"
        case .newItem: return "n"
        case .openProject: return "o"
        case .switchProject1: return "1"
        case .switchProject2: return "2"
        case .switchProject3: return "3"
        case .switchProject4: return "4"
        case .switchProject5: return "5"
        case .switchProject6: return "6"
        case .switchProject7: return "7"
        case .switchProject8: return "8"
        case .switchProject9: return "9"
        case .closeEntry: return "w"
        case .refresh: return "r"
        }
    }

    var defaultModifierMask: NSEvent.ModifierFlags {
        return .command
    }
}

// MARK: - Stored Binding

struct StoredBinding: Codable {
    let keyEquivalent: String
    let modifiers: UInt  // NSEvent.ModifierFlags.rawValue
}

// MARK: - KeybindingManager

class KeybindingManager {
    static let shared = KeybindingManager()

    private let defaultsKey = "PPGCustomKeybindings"

    private var customBindings: [String: StoredBinding] = [:]

    init() {
        loadBindings()
    }

    // MARK: - Persistence

    private func loadBindings() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: StoredBinding].self, from: data) else {
            return
        }
        customBindings = decoded
    }

    private func saveBindings() {
        guard let data = try? JSONEncoder().encode(customBindings) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    // MARK: - Query

    func keyEquivalent(for action: BindableAction) -> String {
        customBindings[action.rawValue]?.keyEquivalent ?? action.defaultKeyEquivalent
    }

    func modifierMask(for action: BindableAction) -> NSEvent.ModifierFlags {
        if let stored = customBindings[action.rawValue] {
            return NSEvent.ModifierFlags(rawValue: stored.modifiers)
        }
        return action.defaultModifierMask
    }

    func isCustomized(_ action: BindableAction) -> Bool {
        customBindings[action.rawValue] != nil
    }

    // MARK: - Mutation

    /// Set a custom binding. Returns the conflicting action if a duplicate is detected.
    @discardableResult
    func setBinding(for action: BindableAction, keyEquivalent: String, modifiers: NSEvent.ModifierFlags) -> BindableAction? {
        // Check for duplicates
        if let conflict = findConflict(keyEquivalent: keyEquivalent, modifiers: modifiers, excluding: action) {
            return conflict
        }

        customBindings[action.rawValue] = StoredBinding(keyEquivalent: keyEquivalent, modifiers: modifiers.rawValue)
        saveBindings()
        return nil
    }

    func resetAll() {
        customBindings.removeAll()
        saveBindings()
    }

    func resetAction(_ action: BindableAction) {
        customBindings.removeValue(forKey: action.rawValue)
        saveBindings()
    }

    // MARK: - Conflict Detection

    func findConflict(keyEquivalent: String, modifiers: NSEvent.ModifierFlags, excluding: BindableAction) -> BindableAction? {
        for action in BindableAction.allCases where action != excluding {
            let key = self.keyEquivalent(for: action)
            let mods = self.modifierMask(for: action)
            if key == keyEquivalent && mods == modifiers {
                return action
            }
        }
        return nil
    }

    // MARK: - Apply to Menu

    func applyBindings(to menu: NSMenu) {
        applyBindingsRecursive(menu)
    }

    private func applyBindingsRecursive(_ menu: NSMenu) {
        for item in menu.items {
            if let tag = menuItemAction(for: item) {
                item.keyEquivalent = keyEquivalent(for: tag)
                item.keyEquivalentModifierMask = modifierMask(for: tag)
            }
            if let submenu = item.submenu {
                applyBindingsRecursive(submenu)
            }
        }
    }

    /// Map a menu item to its BindableAction using the item's tag.
    private func menuItemAction(for item: NSMenuItem) -> BindableAction? {
        guard item.tag != 0 else { return nil }
        return BindableAction(rawValue: menuTagToActionId(item.tag))
    }

    // MARK: - Display Helpers

    static func displayString(keyEquivalent: String, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyEquivalent.uppercased())
        return parts.joined()
    }

    func displayString(for action: BindableAction) -> String {
        KeybindingManager.displayString(
            keyEquivalent: keyEquivalent(for: action),
            modifiers: modifierMask(for: action)
        )
    }
}

// MARK: - Menu Tag Constants

/// Unique tags for identifying menu items that support rebinding.
/// We use raw int tags so the menu items can be looked up after creation.
let kMenuTagQuit       = 100
let kMenuTagNew        = 101
let kMenuTagOpen       = 102
let kMenuTagClose      = 103
let kMenuTagRefresh    = 104
let kMenuTagProject1   = 111
let kMenuTagProject2   = 112
let kMenuTagProject3   = 113
let kMenuTagProject4   = 114
let kMenuTagProject5   = 115
let kMenuTagProject6   = 116
let kMenuTagProject7   = 117
let kMenuTagProject8   = 118
let kMenuTagProject9   = 119

func menuTagToActionId(_ tag: Int) -> String {
    switch tag {
    case kMenuTagQuit: return BindableAction.quit.rawValue
    case kMenuTagNew: return BindableAction.newItem.rawValue
    case kMenuTagOpen: return BindableAction.openProject.rawValue
    case kMenuTagClose: return BindableAction.closeEntry.rawValue
    case kMenuTagRefresh: return BindableAction.refresh.rawValue
    case kMenuTagProject1: return BindableAction.switchProject1.rawValue
    case kMenuTagProject2: return BindableAction.switchProject2.rawValue
    case kMenuTagProject3: return BindableAction.switchProject3.rawValue
    case kMenuTagProject4: return BindableAction.switchProject4.rawValue
    case kMenuTagProject5: return BindableAction.switchProject5.rawValue
    case kMenuTagProject6: return BindableAction.switchProject6.rawValue
    case kMenuTagProject7: return BindableAction.switchProject7.rawValue
    case kMenuTagProject8: return BindableAction.switchProject8.rawValue
    case kMenuTagProject9: return BindableAction.switchProject9.rawValue
    default: return ""
    }
}
