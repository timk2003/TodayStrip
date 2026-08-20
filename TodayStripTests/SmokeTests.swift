import Testing
@testable import TodayStrip

@Suite("Test target wiring")
struct SmokeTests {
    @Test func allModulesAreEnumerated() {
        #expect(StripItemKind.allCases.count == 6)
    }
}
