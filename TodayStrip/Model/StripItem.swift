import Foundation

/// The six things the strip can talk about. Each one is produced by exactly one `StripSource`.
nonisolated enum StripItemKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case event
    case timer
    case focus
    case battery
    case weather
    case note

    nonisolated var id: String { rawValue }

    /// Display name, used in Settings.
    var title: String {
        switch self {
        case .event: "Next event"
        case .timer: "Timer"
        case .focus: "Focus"
        case .battery: "Battery"
        case .weather: "Weather"
        case .note: "Today's note"
        }
    }

    /// Icon representing the module itself (not a particular state of it).
    var moduleSymbol: String {
        switch self {
        case .event: "calendar"
        case .timer: "timer"
        case .focus: "moon.fill"
        case .battery: "battery.100"
        case .weather: "cloud.sun"
        case .note: "square.and.pencil"
        }
    }

    /// Tie-breaker when two items claim the same priority. Lower wins the strip.
    var rank: Int {
        switch self {
        case .event: 0
        case .timer: 1
        case .focus: 2
        case .battery: 3
        case .weather: 4
        case .note: 5
        }
    }
}

/// How loudly an item is asking for the menu bar.
///
/// The rotator reads this in two ways: `pinned` stops rotation entirely, and anything
/// at `urgent` or above interrupts the current slot instead of waiting its turn.
nonisolated enum StripPriority: Int, Comparable, Sendable {
    /// Nice to know, no urgency: weather, today's note.
    case ambient = 0
    /// Relevant right now: an event later today, an active Focus.
    case normal = 1
    /// Approaching: event within 15 minutes, battery below 20%.
    case elevated = 2
    /// Happening: event within 5 minutes, battery below 10%.
    case urgent = 3
    /// Owns the strip until it resolves: a running timer, an event about to start.
    case pinned = 4

    nonisolated static func < (lhs: StripPriority, rhs: StripPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// How long this item stays on screen during rotation. More urgent means more dwell.
    var dwell: TimeInterval {
        switch self {
        case .ambient: 4
        case .normal: 5
        case .elevated: 6
        case .urgent: 8
        case .pinned: .infinity
        }
    }
}

/// A tint hint. Kept abstract so the model stays free of AppKit.
nonisolated enum StripTint: Sendable {
    case normal
    case warning
    case critical
}

/// One rendered candidate for the menu bar.
///
/// Sources rebuild these from scratch on every change rather than mutating them, which keeps
/// `Equatable` meaningful: if the item is equal, nothing needs redrawing.
nonisolated struct StripItem: Identifiable, Equatable, Sendable {
    var kind: StripItemKind
    var priority: StripPriority
    var symbolName: String
    var text: String
    /// Shown instead of `text` when the menu bar is tight. Falls back to `text`.
    var compactText: String?
    var tint: StripTint

    nonisolated var id: StripItemKind { kind }

    init(
        kind: StripItemKind,
        priority: StripPriority,
        symbolName: String,
        text: String,
        compactText: String? = nil,
        tint: StripTint = .normal
    ) {
        self.kind = kind
        self.priority = priority
        self.symbolName = symbolName
        self.text = text
        self.compactText = compactText
        self.tint = tint
    }
}
