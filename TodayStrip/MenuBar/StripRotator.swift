import Foundation

/// Decides which single item the menu bar is showing right now.
///
/// The rotation is deliberately boring: candidates are sorted by priority, shown in turn, and each
/// gets a dwell time that grows with its priority. Two rules break the round-robin, and they are
/// the only reason this class exists rather than a modulo on a timer:
///
/// - A `pinned` item (a running timer, a meeting about to start) holds the strip and rotation stops.
/// - An item that becomes `urgent` or higher cuts in immediately instead of waiting its turn.
///
/// All time comes in through `tick(_:)`, so tests drive it without waiting on a real clock.
@MainActor
final class StripRotator {
    private(set) var current: StripItem?

    /// Called whenever the displayed item changes, including a content-only change such as a
    /// countdown ticking down.
    var onChange: ((StripItem?) -> Void)?

    /// Multiplier on every dwell time. Higher is slower.
    var speed: Double = 1

    /// While paused (the popover is open), the current item stays put.
    private(set) var isPaused = false

    private var items: [StripItem] = []
    private var currentKind: StripItemKind?
    private var slotElapsed: TimeInterval = 0

    // MARK: - Input

    /// Replaces the candidate set. Safe to call at any rate; unchanged input is a no-op.
    func setItems(_ newItems: [StripItem]) {
        let sorted = newItems.sorted(by: Self.ordering)
        guard sorted != items else { return }

        let previous = items
        items = sorted

        if let interrupting = Self.interruption(from: previous, to: sorted, showing: currentKind) {
            select(interrupting)
            return
        }

        // Keep showing whatever is on screen if it is still a candidate, so a routine refresh
        // never yanks the strip out from under someone mid-read.
        if let currentKind, sorted.contains(where: { $0.kind == currentKind }) {
            emitCurrent()
        } else {
            select(sorted.first?.kind)
        }
    }

    /// Advances the rotation clock. `delta` is seconds since the previous call.
    func tick(_ delta: TimeInterval) {
        guard !isPaused, !items.isEmpty else { return }

        guard let dwell = currentDwell() else {
            // A pinned item owns the strip until its priority drops.
            slotElapsed = 0
            return
        }

        slotElapsed += delta
        guard slotElapsed >= dwell else { return }
        advance()
    }

    /// Moves to the next candidate immediately.
    func advance() {
        guard items.count > 1 else {
            slotElapsed = 0
            return
        }
        let index = currentKind.flatMap { kind in items.firstIndex { $0.kind == kind } } ?? -1
        let next = items[(index + 1) % items.count]
        select(next.kind)
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    // MARK: - Selection

    private func select(_ kind: StripItemKind?) {
        currentKind = kind
        slotElapsed = 0
        emitCurrent()
    }

    private func emitCurrent() {
        let item = currentKind.flatMap { kind in items.first { $0.kind == kind } }
        guard item != current else { return }
        current = item
        onChange?(item)
    }

    /// `nil` while a pinned item is showing, which is how `tick` knows not to rotate.
    private func currentDwell() -> TimeInterval? {
        guard let item = current else { return 0 }
        guard item.priority != .pinned else { return nil }
        return item.priority.dwell * max(0.2, speed)
    }

    // MARK: - Rules

    /// Highest priority first; ties broken by a fixed module order so the sequence is stable
    /// from one refresh to the next.
    private nonisolated static func ordering(_ lhs: StripItem, _ rhs: StripItem) -> Bool {
        lhs.priority == rhs.priority
            ? lhs.kind.rank < rhs.kind.rank
            : lhs.priority > rhs.priority
    }

    /// The item that has earned the right to interrupt, if any.
    ///
    /// Interrupting requires being at least `urgent` and being *newly* so — otherwise a battery
    /// sitting at 8% would re-interrupt on every refresh and the strip would never move again.
    private nonisolated static func interruption(
        from previous: [StripItem],
        to current: [StripItem],
        showing kind: StripItemKind?
    ) -> StripItemKind? {
        for item in current where item.priority >= .urgent {
            guard item.kind != kind else { return nil }
            let before = previous.first { $0.kind == item.kind }
            if before == nil || before!.priority < item.priority {
                return item.kind
            }
        }
        return nil
    }
}
