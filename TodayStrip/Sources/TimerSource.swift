import Foundation
import AppKit
import UserNotifications
import Observation

/// Countdown and stopwatch in one source.
///
/// Both modes are stored as an absolute `Date` plus, while paused, the frozen interval. Deriving
/// the display from wall-clock time rather than counting ticks means the timer stays correct
/// across sleep, a missed tick, or a busy main thread — the ticker only decides when to redraw.
@Observable
final class TimerSource: StripSource {
    nonisolated enum Mode: Equatable, Sendable {
        case idle
        case countdown
        case stopwatch
        /// A countdown that reached zero and is waiting to be acknowledged.
        case finished
    }

    let kind = StripItemKind.timer

    @ObservationIgnored var onChange: (() -> Void)?
    private(set) var currentItem: StripItem?

    private(set) var mode: Mode = .idle
    private(set) var isRunning = false

    /// The countdown's full length, kept for the progress ratio after it starts draining.
    private(set) var total: TimeInterval = 0

    /// The clock as of the last tick or control action.
    ///
    /// Stored rather than read from `Date()` on each access, so that the passage of time is part
    /// of the observation graph. Without it, `remaining` and `elapsed` have no observable
    /// dependency that changes while the timer runs, and a SwiftUI view reading them is never
    /// invalidated — the menu bar would tick along while the popover showed a frozen clock.
    private(set) var now = Date()

    private var deadline: Date?
    private var startDate: Date?
    private var frozen: TimeInterval = 0

    private var ticker: Timer?

    // MARK: - Derived state

    /// Seconds left on the countdown, never negative.
    var remaining: TimeInterval {
        switch mode {
        case .countdown:
            guard isRunning, let deadline else { return frozen }
            return max(0, deadline.timeIntervalSince(now))
        case .finished:
            return 0
        case .idle, .stopwatch:
            return 0
        }
    }

    /// Seconds counted up by the stopwatch.
    var elapsed: TimeInterval {
        guard mode == .stopwatch else { return 0 }
        guard isRunning, let startDate else { return frozen }
        return frozen + now.timeIntervalSince(startDate)
    }

    /// 0...1 through the countdown, or `nil` when there is nothing to show progress for.
    var progress: Double? {
        guard mode == .countdown || mode == .finished, total > 0 else { return nil }
        return min(1, max(0, 1 - remaining / total))
    }

    // MARK: - StripSource

    func start() {
        publish()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
    }

    func refresh() {
        publish()
    }

    // MARK: - Controls

    func startCountdown(minutes: Int) {
        startCountdown(duration: TimeInterval(minutes) * 60)
    }

    func startCountdown(duration: TimeInterval) {
        guard duration > 0 else { return }
        now = Date()
        mode = .countdown
        total = duration
        deadline = now.addingTimeInterval(duration)
        frozen = duration
        isRunning = true
        startTicking()
        publish()
    }

    func startStopwatch() {
        now = Date()
        mode = .stopwatch
        total = 0
        startDate = now
        frozen = 0
        isRunning = true
        startTicking()
        publish()
    }

    func pause() {
        guard isRunning else { return }
        now = Date()
        switch mode {
        case .countdown:
            frozen = remaining
            deadline = nil
        case .stopwatch:
            frozen = elapsed
            startDate = nil
        case .idle, .finished:
            return
        }
        isRunning = false
        stopTicking()
        publish()
    }

    func resume() {
        guard !isRunning else { return }
        now = Date()
        switch mode {
        case .countdown:
            guard frozen > 0 else { return }
            deadline = now.addingTimeInterval(frozen)
        case .stopwatch:
            startDate = now
        case .idle, .finished:
            return
        }
        isRunning = true
        startTicking()
        publish()
    }

    func toggle() {
        isRunning ? pause() : resume()
    }

    /// Adds time to a running or paused countdown. Negative values subtract.
    func extend(by interval: TimeInterval) {
        guard mode == .countdown || mode == .finished else { return }
        now = Date()
        if mode == .finished {
            guard interval > 0 else { return }
            mode = .countdown
            total = interval
            frozen = interval
            deadline = now.addingTimeInterval(interval)
            isRunning = true
            startTicking()
        } else if isRunning, let deadline {
            let next = max(now, deadline.addingTimeInterval(interval))
            self.deadline = next
            total = max(total + interval, next.timeIntervalSince(now))
        } else {
            frozen = max(0, frozen + interval)
            total = max(total + interval, frozen)
        }
        publish()
    }

    func reset() {
        now = Date()
        mode = .idle
        isRunning = false
        deadline = nil
        startDate = nil
        frozen = 0
        total = 0
        stopTicking()
        publish()
    }

    // MARK: - Ticking

    private func startTicking() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common keeps the countdown moving while a menu or the popover is tracking events.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        now = Date()
        if mode == .countdown, isRunning, remaining <= 0 {
            finish()
            return
        }
        publish()
    }

    private func finish() {
        mode = .finished
        isRunning = false
        deadline = nil
        stopTicking()
        publish()
        notifyFinished()
    }

    private func notifyFinished() {
        if Preferences.shared.playSoundOnTimerEnd {
            NSSound(named: "Glass")?.play()
        }
        let content = UNMutableNotificationContent()
        content.title = "Timer finished"
        content.body = total > 0 ? "\(Self.spokenDuration(total)) are up." : "Time is up."
        content.sound = nil // The NSSound above already played; a second chime would be noise.
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Publishing

    private func publish() {
        let item: StripItem?
        switch mode {
        case .idle:
            item = nil

        case .countdown:
            let clock = Self.clock(remaining)
            item = StripItem(
                kind: .timer,
                priority: isRunning ? .pinned : .normal,
                symbolName: isRunning ? "timer" : "pause.circle",
                text: clock,
                compactText: clock,
                tint: remaining <= 60 ? .warning : .normal
            )

        case .stopwatch:
            let clock = Self.clock(elapsed)
            item = StripItem(
                kind: .timer,
                priority: isRunning ? .pinned : .normal,
                symbolName: isRunning ? "stopwatch" : "pause.circle",
                text: clock,
                compactText: clock
            )

        case .finished:
            item = StripItem(
                kind: .timer,
                priority: .urgent,
                symbolName: "bell.fill",
                text: "Time's up",
                compactText: "Done",
                tint: .critical
            )
        }

        guard item != currentItem else { return }
        currentItem = item
        onChange?()
    }

    // MARK: - Formatting

    /// `12:34` under an hour, `1:02:03` above it.
    nonisolated static func clock(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    nonisolated static func spokenDuration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: interval) ?? "\(Int(interval)) seconds"
    }
}
