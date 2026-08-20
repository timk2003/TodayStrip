import Foundation
import Testing
@testable import TodayStrip

@Suite("URL commands")
struct URLCommandTests {
    private func parse(_ string: String) -> URLCommand? {
        URL(string: string).flatMap(URLCommand.init(url:))
    }

    @Test func startsACountdownFromThePath() {
        #expect(parse("todaystrip://timer/25") == .startCountdown(minutes: 25))
    }

    @Test func startsACountdownFromAQueryParameter() {
        #expect(parse("todaystrip://timer?minutes=25") == .startCountdown(minutes: 25))
    }

    @Test func startsTheStopwatch() {
        #expect(parse("todaystrip://stopwatch") == .startStopwatch)
    }

    @Test func stopsTheTimer() {
        #expect(parse("todaystrip://timer/stop") == .stopTimer)
    }

    @Test func setsTodaysNote() {
        #expect(parse("todaystrip://note?text=Ship%20the%20release") == .setNote("Ship the release"))
    }

    @Test func opensThePanel() {
        #expect(parse("todaystrip://open") == .openPanel)
    }

    @Test func rejectsAForeignScheme() {
        #expect(parse("https://timer/25") == nil)
    }

    @Test func rejectsAnUnknownCommand() {
        #expect(parse("todaystrip://selfdestruct") == nil)
    }

    @Test func rejectsANonPositiveDuration() {
        #expect(parse("todaystrip://timer/0") == nil)
        #expect(parse("todaystrip://timer/-5") == nil)
    }

    @Test func rejectsANonNumericDuration() {
        #expect(parse("todaystrip://timer/soon") == nil)
    }

    @Test func rejectsAnEmptyNote() {
        #expect(parse("todaystrip://note?text=%20%20") == nil)
    }
}
