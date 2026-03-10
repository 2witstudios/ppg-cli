import Testing
import SwiftUI
@testable import PPGMobile

@Suite("AgentVariant")
struct AgentVariantTests {
    @Test("resolves known agent types case-insensitively")
    func resolvesKnownTypes() {
        #expect(AgentVariant.from("claude") == .claude)
        #expect(AgentVariant.from("codex") == .codex)
        #expect(AgentVariant.from("opencode") == .opencode)
        #expect(AgentVariant.from("Claude") == .claude)
        #expect(AgentVariant.from("CODEX") == .codex)
    }

    @Test("returns nil for unknown agent types")
    func returnsNilForUnknown() {
        #expect(AgentVariant.from("gpt4") == nil)
        #expect(AgentVariant.from("") == nil)
        #expect(AgentVariant.from("custom-agent") == nil)
    }

    @Test("every variant has a non-empty displayName and sfSymbol")
    func displayProperties() {
        for variant in AgentVariant.allCases {
            #expect(!variant.displayName.isEmpty)
            #expect(!variant.sfSymbol.isEmpty)
        }
    }
}
