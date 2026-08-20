import Foundation

/// The most useful thing to say about the calendar right now.
///
/// The distinction that matters is between a meeting you are about to walk into and one that is
/// hours away. For the first, the countdown is the news. For the second, the meeting is not the
/// news at all — the runway before it is, because that is what decides whether you start
/// something big now.
nonisolated enum CalendarHeadline: Equatable, Sendable {
    case inProgress(minutesLeft: Int)
    case startingSoon(minutes: Int)
    case freeUntil(Date)
    case clear

    /// Beyond this, a meeting stops being a countdown and becomes a deadline for your free time.
    static let soonHorizon = 60

    static func of(_ event: CalendarSource.Event?, now: Date = Date()) -> CalendarHeadline {
        guard let event else { return .clear }

        if event.start <= now, now < event.end {
            return .inProgress(minutesLeft: Int((event.end.timeIntervalSince(now) / 60).rounded(.up)))
        }

        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.down))
        return minutes <= soonHorizon ? .startingSoon(minutes: minutes) : .freeUntil(event.start)
    }
}
