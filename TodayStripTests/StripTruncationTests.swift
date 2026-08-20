import Testing
@testable import TodayStrip

@Suite("Menu bar truncation")
struct StripTruncationTests {
    @Test func keepsTheFullTextWhenItFits() {
        #expect(StatusItemController.fit(full: "Standup in 12m", compact: "in 12m", limit: 28) == "Standup in 12m")
    }

    @Test func fallsBackToTheCompactFormBeforeTruncating() {
        #expect(StatusItemController.fit(full: "Quarterly planning in 12m", compact: "in 12m", limit: 12) == "in 12m")
    }

    @Test func truncatesWhenEvenTheCompactFormIsTooLong() {
        let result = StatusItemController.fit(full: "Quarterly planning review", compact: nil, limit: 10)
        #expect(result == "Quarterly…")
        #expect(result.count == 10)
    }
}
