import Foundation
import Observation

/// User settings, backed directly by `UserDefaults`.
///
/// Properties are computed rather than stored so that `UserDefaults` stays the single source of
/// truth (no cache to keep in sync), while `access`/`withMutation` still give SwiftUI real
/// observation. Defaults live in `fallback` so a fresh install and a reset behave identically.
@Observable
final class Preferences {
    static let shared = Preferences()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Modules

    /// Which modules may appear in the strip at all.
    var enabledKinds: Set<StripItemKind> {
        get {
            access(keyPath: \.enabledKinds)
            guard let raw = defaults.array(forKey: Key.enabledKinds) as? [String] else {
                return Set(StripItemKind.allCases)
            }
            return Set(raw.compactMap(StripItemKind.init(rawValue:)))
        }
        set {
            withMutation(keyPath: \.enabledKinds) {
                defaults.set(newValue.map(\.rawValue).sorted(), forKey: Key.enabledKinds)
            }
        }
    }

    func isEnabled(_ kind: StripItemKind) -> Bool {
        enabledKinds.contains(kind)
    }

    func setEnabled(_ kind: StripItemKind, _ enabled: Bool) {
        var kinds = enabledKinds
        if enabled { kinds.insert(kind) } else { kinds.remove(kind) }
        enabledKinds = kinds
    }

    // MARK: - Strip appearance

    /// Multiplier on every priority's dwell time. 1.0 keeps the defaults from `StripPriority`.
    var rotationSpeed: Double {
        get {
            access(keyPath: \.rotationSpeed)
            return number(Key.rotationSpeed, 1.0)
        }
        set { withMutation(keyPath: \.rotationSpeed) { defaults.set(newValue, forKey: Key.rotationSpeed) } }
    }

    /// Longest strip text before it gets truncated, in characters.
    var maxWidth: Int {
        get {
            access(keyPath: \.maxWidth)
            return integer(Key.maxWidth, 28)
        }
        set { withMutation(keyPath: \.maxWidth) { defaults.set(newValue, forKey: Key.maxWidth) } }
    }

    /// Hide text entirely and show only the current item's icon.
    var iconOnly: Bool {
        get {
            access(keyPath: \.iconOnly)
            return flag(Key.iconOnly, false)
        }
        set { withMutation(keyPath: \.iconOnly) { defaults.set(newValue, forKey: Key.iconOnly) } }
    }

    // MARK: - Calendar

    /// Calendar identifiers the user has switched off. Everything not listed is included.
    var excludedCalendarIDs: Set<String> {
        get {
            access(keyPath: \.excludedCalendarIDs)
            return Set(defaults.stringArray(forKey: Key.excludedCalendars) ?? [])
        }
        set {
            withMutation(keyPath: \.excludedCalendarIDs) {
                defaults.set(newValue.sorted(), forKey: Key.excludedCalendars)
            }
        }
    }

    /// How far ahead to look for the next event, in minutes.
    var eventLookAheadMinutes: Int {
        get {
            access(keyPath: \.eventLookAheadMinutes)
            return integer(Key.eventLookAhead, 12 * 60)
        }
        set { withMutation(keyPath: \.eventLookAheadMinutes) { defaults.set(newValue, forKey: Key.eventLookAhead) } }
    }

    /// Skip events the user has declined.
    var hideDeclinedEvents: Bool {
        get {
            access(keyPath: \.hideDeclinedEvents)
            return flag(Key.hideDeclined, true)
        }
        set { withMutation(keyPath: \.hideDeclinedEvents) { defaults.set(newValue, forKey: Key.hideDeclined) } }
    }

    // MARK: - Weather

    var useCurrentLocation: Bool {
        get {
            access(keyPath: \.useCurrentLocation)
            return flag(Key.useCurrentLocation, true)
        }
        set { withMutation(keyPath: \.useCurrentLocation) { defaults.set(newValue, forKey: Key.useCurrentLocation) } }
    }

    /// Manually chosen place, used when `useCurrentLocation` is off.
    var manualPlace: Place? {
        get {
            access(keyPath: \.manualPlace)
            guard let data = defaults.data(forKey: Key.manualPlace) else { return nil }
            return try? JSONDecoder().decode(Place.self, from: data)
        }
        set {
            withMutation(keyPath: \.manualPlace) {
                defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.manualPlace)
            }
        }
    }

    var temperatureUnit: TemperatureUnit {
        get {
            access(keyPath: \.temperatureUnit)
            guard let raw = defaults.string(forKey: Key.temperatureUnit),
                  let unit = TemperatureUnit(rawValue: raw)
            else { return .system }
            return unit
        }
        set { withMutation(keyPath: \.temperatureUnit) { defaults.set(newValue.rawValue, forKey: Key.temperatureUnit) } }
    }

    // MARK: - Timer

    /// Countdown presets offered in the popover, in minutes.
    var timerPresets: [Int] {
        get {
            access(keyPath: \.timerPresets)
            let stored = defaults.array(forKey: Key.timerPresets) as? [Int]
            return stored?.isEmpty == false ? stored! : [5, 15, 25, 45]
        }
        set { withMutation(keyPath: \.timerPresets) { defaults.set(newValue, forKey: Key.timerPresets) } }
    }

    var playSoundOnTimerEnd: Bool {
        get {
            access(keyPath: \.playSoundOnTimerEnd)
            return flag(Key.timerSound, true)
        }
        set { withMutation(keyPath: \.playSoundOnTimerEnd) { defaults.set(newValue, forKey: Key.timerSound) } }
    }

    // MARK: - General

    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return LoginItem.isEnabled
        }
        set {
            withMutation(keyPath: \.launchAtLogin) { LoginItem.setEnabled(newValue) }
        }
    }

    // MARK: - Helpers

    private func flag(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private func integer(_ key: String, _ fallback: Int) -> Int {
        defaults.object(forKey: key) as? Int ?? fallback
    }

    private func number(_ key: String, _ fallback: Double) -> Double {
        defaults.object(forKey: key) as? Double ?? fallback
    }

    private enum Key {
        static let enabledKinds = "enabledKinds"
        static let rotationSpeed = "rotationSpeed"
        static let maxWidth = "maxWidth"
        static let iconOnly = "iconOnly"
        static let excludedCalendars = "excludedCalendarIDs"
        static let eventLookAhead = "eventLookAheadMinutes"
        static let hideDeclined = "hideDeclinedEvents"
        static let useCurrentLocation = "useCurrentLocation"
        static let manualPlace = "manualPlace"
        static let temperatureUnit = "temperatureUnit"
        static let timerPresets = "timerPresets"
        static let timerSound = "playSoundOnTimerEnd"
    }
}

/// A geocoded location the user picked by name.
nonisolated struct Place: Codable, Equatable, Sendable, Identifiable {
    var name: String
    var admin: String?
    var country: String?
    var latitude: Double
    var longitude: Double

    nonisolated var id: String { "\(latitude),\(longitude)" }

    var subtitle: String {
        [admin, country].compactMap { $0 }.joined(separator: ", ")
    }
}

nonisolated enum TemperatureUnit: String, CaseIterable, Sendable {
    case system
    case celsius
    case fahrenheit

    var title: String {
        switch self {
        case .system: "System"
        case .celsius: "Celsius"
        case .fahrenheit: "Fahrenheit"
        }
    }

    /// Open-Meteo's parameter value, or `nil` to accept its metric default.
    var apiValue: String? {
        switch self {
        case .celsius: nil
        case .fahrenheit: "fahrenheit"
        case .system: Locale.current.measurementSystem == .us ? "fahrenheit" : nil
        }
    }

    var symbol: String {
        apiValue == "fahrenheit" ? "°F" : "°C"
    }
}
