import SwiftUI

/// Known agent types with their display properties.
///
/// Maps to the `agentType` field on `AgentEntry`. New variants can be added
/// without schema changes since `agentType` is a free-form string — unknown
/// values fall back to `AgentVariant.unknown`.
enum AgentVariant: String, CaseIterable, Identifiable {
    case claude
    case codex
    case opencode

    var id: String { rawValue }

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .claude:   "Claude"
        case .codex:    "Codex"
        case .opencode: "OpenCode"
        }
    }

    /// SF Symbol icon for this agent type.
    var sfSymbol: String {
        switch self {
        case .claude:   "brain.head.profile"
        case .codex:    "terminal"
        case .opencode: "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Brand color for this agent type.
    var color: Color {
        switch self {
        case .claude:   .orange
        case .codex:    .cyan
        case .opencode: .purple
        }
    }

    /// Resolve an `agentType` string to a known variant, or `nil` if unknown.
    static func from(_ agentType: String) -> AgentVariant? {
        AgentVariant(rawValue: agentType.lowercased())
    }
}

// MARK: - AgentEntry integration

extension AgentEntry {
    /// The known variant for this agent, or `nil` for custom agent types.
    var variant: AgentVariant? {
        AgentVariant.from(agentType)
    }

    /// Display name — uses the variant's name if known, otherwise the raw `agentType`.
    var displayName: String {
        variant?.displayName ?? agentType
    }

    /// Icon — uses the variant's symbol if known, otherwise a generic terminal icon.
    var iconName: String {
        variant?.sfSymbol ?? "terminal"
    }

    /// Color — uses the variant's color if known, otherwise secondary.
    var brandColor: Color {
        variant?.color ?? .secondary
    }
}
