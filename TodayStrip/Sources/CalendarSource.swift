import Foundation
import EventKit
import Observation
import os
import AppKit

/// The next event worth walking into a room for.
///
/// EventKit is queried on change and every two minutes; the countdown text is recomputed every
/// fifteen seconds from the cached event, so the strip stays accurate without re-running a
/// predicate query for every tick. Events are copied into a plain value type, because `EKEvent`
/// objects become stale once the store reloads underneath them.
@Observable
final class CalendarSource: StripSource {
    nonisolated struct Event: Equatable, Sendable, Identifiable {
        var id: String
        var title: String
        var start: Date
        var end: Date
        var location: String?
        var calendarTitle: String
        var link: MeetingLink?

        var isInProgress: Bool {
            let now = Date()
            return start <= now && now < end
        }

        var minutesUntilStart: Int {
            Int((start.timeIntervalSinceNow / 60).rounded(.down))
        }
    }

    nonisolated struct CalendarInfo: Equatable, Sendable, Identifiable {
        var id: String
        var title: String
        var sourceTitle: String
    }

    let kind = StripItemKind.event

    @ObservationIgnored var onChange: (() -> Void)?
    private(set) var currentItem: StripItem?

    private(set) var nextEvent: Event?
    private(set) var upcoming: [Event] = []
    private(set) var availableCalendars: [CalendarInfo] = []
    private(set) var authorization: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    private static let log = Logger(subsystem: Logger.subsystem, category: "Calendar")

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private let preferences: Preferences
    private var queryTicker: Timer?
    private var displayTicker: Timer?
    private var observer: NSObjectProtocol?
    private var lastQuery: Date = .distantPast

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
    }

    // MARK: - StripSource

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.query() }
        }

        // Redrawing the countdown is cheap; re-running the query is not.
        displayTicker = scheduled(every: 15) { [weak self] in self?.publish() }
        queryTicker = scheduled(every: 120) { [weak self] in self?.query() }

        Task { await requestAccessIfNeeded() }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        displayTicker?.invalidate()
        displayTicker = nil
        queryTicker?.invalidate()
        queryTicker = nil
    }

    func refresh() {
        query()
    }

    // MARK: - Access

    func requestAccessIfNeeded() async {
        authorization = EKEventStore.authorizationStatus(for: .event)
        NSLog("TS/cal: entry status=%d", authorization.rawValue)
        guard authorization == .notDetermined else {
            if hasAccess { query() }
            return
        }
        do {
            let granted = try await store.requestFullAccessToEvents()
            NSLog("TS/cal: requestFullAccess granted=%@", String(describing: granted))
        } catch {
            NSLog("TS/cal: requestFullAccess threw %@", error.localizedDescription)
            Self.log.error("Calendar access request failed: \(error.localizedDescription)")
        }
        authorization = EKEventStore.authorizationStatus(for: .event)
        NSLog("TS/cal: after status=%d hasAccess=%@", authorization.rawValue, String(describing: hasAccess))
        if hasAccess { query() }
    }

    var hasAccess: Bool {
        authorization == .fullAccess
    }

    // MARK: - Querying

    private func query() {
        guard hasAccess else {
            availableCalendars = []
            apply(events: [])
            return
        }

        let calendars = store.calendars(for: .event)
        availableCalendars = calendars
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source.title) }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }

        let excluded = preferences.excludedCalendarIDs
        let included = calendars.filter { !excluded.contains($0.calendarIdentifier) }
        guard !included.isEmpty else {
            apply(events: [])
            return
        }

        NSLog("TS/cal: query cals=%d included=%d", calendars.count, included.count)
        let now = Date()
        let end = now.addingTimeInterval(TimeInterval(preferences.eventLookAheadMinutes) * 60)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: included)

        let hideDeclined = preferences.hideDeclinedEvents
        let events = store.events(matching: predicate)
            .filter { isWorthShowing($0, hideDeclined: hideDeclined) }
            .sorted { $0.startDate < $1.startDate }
            .prefix(10)
            .map(Self.value(from:))

        NSLog("TS/cal: matched %d events", events.count)
        lastQuery = now
        apply(events: Array(events))
    }

    /// All-day events describe the day, not a moment, so they never become "in 5 minutes".
    /// Cancelled and declined events are noise the user has already dismissed once.
    private func isWorthShowing(_ event: EKEvent, hideDeclined: Bool) -> Bool {
        guard !event.isAllDay, event.status != .canceled else { return false }
        guard let end = event.endDate, end > Date() else { return false }
        if hideDeclined,
           let me = event.attendees?.first(where: { $0.isCurrentUser }),
           me.participantStatus == .declined {
            return false
        }
        return true
    }

    private nonisolated static func value(from event: EKEvent) -> Event {
        Event(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title?.trimmed.isEmpty == false ? event.title : "Untitled event",
            start: event.startDate,
            end: event.endDate,
            location: event.location?.trimmed,
            calendarTitle: event.calendar?.title ?? "",
            link: MeetingLink.detect(url: event.url, location: event.location, notes: event.notes)
        )
    }

    private func apply(events: [Event]) {
        upcoming = events
        nextEvent = events.first
        publish()
    }

    // MARK: - Publishing

    private func publish() {
        // The cached event eventually ends; drop it rather than showing a finished meeting.
        if let event = nextEvent, event.end <= Date() {
            query()
            return
        }

        let item = nextEvent.map { event -> StripItem in
            let minutes = event.minutesUntilStart
            let priority: StripPriority
            if event.isInProgress {
                priority = .elevated
            } else if minutes <= 2 {
                priority = .pinned
            } else if minutes <= 5 {
                priority = .urgent
            } else if minutes <= 15 {
                priority = .elevated
            } else {
                priority = .normal
            }

            return StripItem(
                kind: .event,
                priority: priority,
                symbolName: event.link != nil ? "video.fill" : "calendar",
                text: "\(event.title) \(Self.relativeText(for: event))",
                compactText: Self.relativeText(for: event),
                tint: priority >= .urgent ? .warning : .normal
            )
        }

        guard item != currentItem else { return }
        currentItem = item
        onChange?()
    }

    /// "now", "in 12m", "ends in 8m" or a wall-clock time, whichever is most useful at that range.
    nonisolated static func relativeText(for event: Event) -> String {
        if event.isInProgress {
            let left = Int((event.end.timeIntervalSinceNow / 60).rounded(.up))
            return left <= 1 ? "ending" : "ends in \(left)m"
        }
        let minutes = event.minutesUntilStart
        switch minutes {
        case ..<1: return "now"
        case ..<60: return "in \(minutes)m"
        default:
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return formatter.string(from: event.start)
        }
    }

    // MARK: - Helpers

    private func scheduled(every interval: TimeInterval, _ body: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { body() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
