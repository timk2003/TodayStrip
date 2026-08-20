import Foundation
import Testing
@testable import TodayStrip

@Suite("Calendar headline")
struct CalendarHeadlineTests {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    private func event(
        startsIn minutes: Double,
        lasting duration: Double = 30,
        title: String = "Standup",
        link: MeetingLink? = nil
    ) -> CalendarSource.Event {
        let start = now.addingTimeInterval(minutes * 60)
        return CalendarSource.Event(
            id: "1",
            title: title,
            start: start,
            end: start.addingTimeInterval(duration * 60),
            location: nil,
            calendarTitle: "Work",
            link: link
        )
    }

    @Test func reportsAnEventThatIsRunning() {
        let headline = CalendarHeadline.of(event(startsIn: -10, lasting: 30), now: now)
        #expect(headline == .inProgress(minutesLeft: 20))
    }

    @Test func countsDownAnEventStartingSoon() {
        #expect(CalendarHeadline.of(event(startsIn: 12), now: now) == .startingSoon(minutes: 12))
    }

    /// The useful fact about a distant meeting is not the meeting, it is the runway before it.
    @Test func leadsWithFreeTimeWhenTheNextEventIsFarOff() {
        let next = event(startsIn: 180)
        #expect(CalendarHeadline.of(next, now: now) == .freeUntil(next.start))
    }

    @Test func sixtyMinutesIsStillFreeTime() {
        let next = event(startsIn: 61)
        #expect(CalendarHeadline.of(next, now: now) == .freeUntil(next.start))
    }

    @Test func sayNothingWhenThereIsNoEvent() {
        #expect(CalendarHeadline.of(nil, now: now) == .clear)
    }
}

@Suite("Calendar strip item")
struct CalendarItemTests {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    private func event(startsIn minutes: Double, link: MeetingLink? = nil) -> CalendarSource.Event {
        let start = now.addingTimeInterval(minutes * 60)
        return CalendarSource.Event(
            id: "1", title: "Standup", start: start, end: start.addingTimeInterval(1800),
            location: nil, calendarTitle: "Work", link: link
        )
    }

    @Test func freeTimeReadsAsFreedom() {
        let item = CalendarSource.item(for: event(startsIn: 180), now: now)
        #expect(item?.text.hasPrefix("Free until") == true)
        #expect(item?.symbolName == "checkmark.circle")
    }

    @Test func anImminentEventIsPinned() {
        #expect(CalendarSource.item(for: event(startsIn: 1), now: now)?.priority == .pinned)
    }

    @Test func aDistantEventStaysNormal() {
        #expect(CalendarSource.item(for: event(startsIn: 180), now: now)?.priority == .normal)
    }

    @Test func noEventMeansNoItem() {
        #expect(CalendarSource.item(for: nil, now: now) == nil)
    }
}

@Suite("Strip click action")
struct StripClickActionTests {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)
    private let zoom = MeetingLink(url: URL(string: "https://acme.zoom.us/j/1")!, service: .zoom)

    private func event(startsIn minutes: Double, link: MeetingLink?) -> CalendarSource.Event {
        let start = now.addingTimeInterval(minutes * 60)
        return CalendarSource.Event(
            id: "1", title: "Standup", start: start, end: start.addingTimeInterval(1800),
            location: nil, calendarTitle: "Work", link: link
        )
    }

    private func eventItem() -> StripItem {
        StripItem(kind: .event, priority: .pinned, symbolName: "video.fill", text: "Standup now")
    }

    /// The whole point: when the call is about to start, one click goes into it.
    @Test func joinsWhenTheStripIsShowingAnImminentCall() {
        let action = AppModel.clickAction(
            displayed: eventItem(),
            nextEvent: event(startsIn: 2, link: zoom),
            now: now
        )
        #expect(action == .join(zoom.url))
    }

    @Test func joinsWhileTheCallIsRunning() {
        let action = AppModel.clickAction(
            displayed: eventItem(),
            nextEvent: event(startsIn: -5, link: zoom),
            now: now
        )
        #expect(action == .join(zoom.url))
    }

    /// A call an hour out is not what the click is for; the panel is more useful.
    @Test func opensThePanelForADistantCall() {
        let action = AppModel.clickAction(
            displayed: eventItem(),
            nextEvent: event(startsIn: 60, link: zoom),
            now: now
        )
        #expect(action == .openPanel)
    }

    @Test func opensThePanelWhenTheEventHasNoLink() {
        let action = AppModel.clickAction(
            displayed: eventItem(),
            nextEvent: event(startsIn: 2, link: nil),
            now: now
        )
        #expect(action == .openPanel)
    }

    /// Hijacking the click while the strip shows the battery would be a nasty surprise.
    @Test func opensThePanelWhenTheStripIsShowingSomethingElse() {
        let battery = StripItem(kind: .battery, priority: .ambient, symbolName: "battery.100percent", text: "80%")
        let action = AppModel.clickAction(
            displayed: battery,
            nextEvent: event(startsIn: 2, link: zoom),
            now: now
        )
        #expect(action == .openPanel)
    }
}
