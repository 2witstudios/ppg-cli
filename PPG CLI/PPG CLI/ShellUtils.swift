import Foundation

/// Shell-escape a string by wrapping in single quotes and escaping embedded single quotes.
func shellEscape(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
