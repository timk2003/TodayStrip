import Foundation
import Observation

/// Wires the sources to the rotator and keeps the shared state the UI reads.
///
/// The sources do not know about each other; this is the only place that knows all six exist.
/// It collects their current items whenever one of them changes, filters by what the user has
/// enabled, and hands the result to the rotator. A half-second heartbeat drives the rotation and
/// also re-collects, which is how preference changes take effect without an extra observer.
@Observable
@MainActor
final class AppModel {
    static let shared = AppModel()

    let preferences: Preferences
    let calendar: CalendarSource
    let timer: TimerSource
    let focus: FocusSource
    let battery: BatterySource
    let weather: WeatherSource
    let note: NoteSource

    @ObservationIgnored let rotator = StripRotator()

    /// What the menu bar is showing, mirrored here so SwiftUI views can read it too.
    private(set) var displayed: StripItem?

    /// Called when the displayed item changes. The menu bar layer subscribes here rather than to
    /// the rotator directly, so the rotator stays owned by exactly one object.
    @ObservationIgnored var onDisplayChange: ((StripItem?) -> Void)?

    @ObservationIgnored private var sources: [any StripSource] = []
    @ObservationIgnored private var heartbeat: Timer?
    @ObservationIgnored private var lastTick = Date()
    @ObservationIgnored private var isRunning = false

    private static let tickInterval: TimeInterval = 0.5

    init(
        preferences: Preferences = .shared,
        calendar: CalendarSource? = nil,
        timer: TimerSource = TimerSource(),
        focus: FocusSource = FocusSource(),
        battery: BatterySource = BatterySource(),
        weather: WeatherSource? = nil,
        note: NoteSource = NoteSource()
    ) {
        self.preferences = preferences
        self.calendar = calendar ?? CalendarSource(preferences: preferences)
        self.timer = timer
        self.focus = focus
        self.battery = battery
        self.weather = weather ?? WeatherSource(preferences: preferences)
        self.note = note

        sources = [self.calendar, self.timer, self.focus, self.battery, self.weather, self.note]
        for index in sources.indices {
            sources[index].onChange = { [weak self] in self?.collect() }
        }
        rotator.onChange = { [weak self] item in
            self?.displayed = item
            self?.onDisplayChange?(item)
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        sources.forEach { $0.start() }
        collect()

        lastTick = Date()
        let heartbeat = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(heartbeat, forMode: .common)
        self.heartbeat = heartbeat
    }

    func stop() {
        isRunning = false
        heartbeat?.invalidate()
        heartbeat = nil
        sources.forEach { $0.stop() }
    }

    /// Re-reads every source from its underlying system, ignoring polling schedules.
    func refreshAll() {
        sources.forEach { $0.refresh() }
        collect()
    }

    // MARK: - Interaction

    /// What a click on the strip should do.
    nonisolated enum ClickAction: Equatable, Sendable {
        case openPanel
        case join(URL)
    }

    /// Decides between opening the panel and joining the call.
    ///
    /// Joining only takes the click when the strip is already showing the event and the call is
    /// essentially now. Both conditions matter: hijacking the click while the strip shows the
    /// battery, or for a meeting an hour out, would be a nasty surprise rather than a shortcut.
    nonisolated static func clickAction(
        displayed: StripItem?,
        nextEvent: CalendarSource.Event?,
        now: Date = Date()
    ) -> ClickAction {
        guard displayed?.kind == .event,
              let event = nextEvent,
              let link = event.link
        else { return .openPanel }

        switch CalendarHeadline.of(event, now: now) {
        case .inProgress:
            return .join(link.url)
        case .startingSoon(let minutes) where minutes <= joinWindowMinutes:
            return .join(link.url)
        case .startingSoon, .freeUntil, .clear:
            return .openPanel
        }
    }

    /// How close the call has to be before the click becomes "join".
    private nonisolated static let joinWindowMinutes = 5

    // MARK: - Rotation

    private func tick() {
        let now = Date()
        // Clamp so waking from sleep does not fast-forward through the whole rotation at once.
        let delta = min(now.timeIntervalSince(lastTick), Self.tickInterval * 4)
        lastTick = now

        collect()
        rotator.speed = preferences.rotationSpeed
        rotator.tick(delta)
    }

    private func collect() {
        let enabled = preferences.enabledKinds
        let items = sources
            .filter { enabled.contains($0.kind) }
            .compactMap(\.currentItem)
        rotator.setItems(items)
    }

    /// Freezes rotation while the popover is open, so the strip doesn't change under the cursor.
    func pauseRotation() {
        rotator.pause()
    }

    func resumeRotation() {
        rotator.resume()
    }
}
