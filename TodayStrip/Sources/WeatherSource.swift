import Foundation
import Observation
import os

/// Current conditions for either the device's location or a place the user picked.
///
/// Refreshes every 15 minutes, which is finer than Open-Meteo's own update cadence and far
/// inside its fair-use limits. A failed fetch keeps the last good reading on screen rather than
/// blanking the strip; only a fetch that never succeeded leaves the module absent.
@Observable
final class WeatherSource: StripSource {
    let kind = StripItemKind.weather

    @ObservationIgnored var onChange: (() -> Void)?
    private(set) var currentItem: StripItem?

    private(set) var conditions: OpenMeteo.Conditions?
    private(set) var placeName: String?
    private(set) var lastError: String?
    private(set) var isLoading = false

    private static let log = Logger(subsystem: Logger.subsystem, category: "Weather")
    private static let refreshInterval: TimeInterval = 15 * 60

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let location: LocationProvider
    private var poller: Timer?
    private var fetch: Task<Void, Never>?

    init(preferences: Preferences = .shared, location: LocationProvider = LocationProvider()) {
        self.preferences = preferences
        self.location = location
        self.location.onChange = { [weak self] _ in
            self?.refresh()
        }
    }

    func start() {
        refresh()
        guard poller == nil else { return }
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        poller = timer
    }

    func stop() {
        fetch?.cancel()
        fetch = nil
        poller?.invalidate()
        poller = nil
    }

    func refresh() {
        guard let target = resolveTarget() else { return }

        fetch?.cancel()
        isLoading = true
        let unit = preferences.temperatureUnit
        fetch = Task { [weak self] in
            do {
                let conditions = try await OpenMeteo.conditions(
                    latitude: target.latitude,
                    longitude: target.longitude,
                    unit: unit
                )
                self?.apply(conditions, placeName: target.name)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.applyFailure(error)
            }
        }
    }

    /// Where to fetch for: either the manual place, or the device location (requesting it if the
    /// provider has nothing yet).
    private func resolveTarget() -> (latitude: Double, longitude: Double, name: String?)? {
        if preferences.useCurrentLocation {
            guard let coordinate = location.coordinate else {
                location.requestLocation()
                if case .denied = location.status {
                    lastError = "Location access is off. Pick a place in Settings."
                }
                isLoading = false
                return nil
            }
            return (coordinate.latitude, coordinate.longitude, placeName)
        }

        guard let place = preferences.manualPlace else {
            lastError = "No place chosen yet."
            isLoading = false
            return nil
        }
        return (place.latitude, place.longitude, place.name)
    }

    private func apply(_ conditions: OpenMeteo.Conditions, placeName: String?) {
        self.conditions = conditions
        if let placeName { self.placeName = placeName }
        lastError = nil
        isLoading = false
        publish()
    }

    private func applyFailure(_ error: Error) {
        Self.log.error("Weather fetch failed: \(error.localizedDescription)")
        lastError = error.localizedDescription
        isLoading = false
        // Keep the previous reading in the strip; stale weather beats a gap.
        publish()
    }

    // MARK: - Publishing

    private func publish() {
        let item = conditions.map { Self.item(for: $0) }
        guard item != currentItem else { return }
        currentItem = item
        onChange?()
    }

    /// Turns a reading into the one line the strip shows.
    ///
    /// Pure and static so the presentation rules can be exercised without a network round trip.
    nonisolated static func item(for conditions: OpenMeteo.Conditions, now: Date = Date()) -> StripItem {
        let temperature = formatted(conditions.temperature, unit: conditions.unitSymbol)

        switch WeatherHeadline.of(conditions, now: now) {
        case .rainStarting(let minutes):
            return StripItem(
                kind: .weather,
                priority: .normal,
                symbolName: "cloud.rain.fill",
                text: "Rain in \(minutes)m",
                compactText: "Rain \(minutes)m"
            )

        case .rainingNow:
            return StripItem(
                kind: .weather,
                priority: .normal,
                symbolName: "cloud.heavyrain.fill",
                text: "Raining, \(temperature)",
                compactText: temperature
            )

        case .frostTonight(let low):
            let lowText = formatted(low, unit: conditions.unitSymbol)
            return StripItem(
                kind: .weather,
                priority: .normal,
                symbolName: "thermometer.snowflake",
                text: "Frost tonight, \(lowText)",
                compactText: "Frost \(lowText)"
            )

        case .conditions:
            return StripItem(
                kind: .weather,
                priority: .ambient,
                symbolName: WeatherCode.symbol(conditions.code, isDay: conditions.isDay),
                text: "\(temperature) \(WeatherCode.description(conditions.code))",
                compactText: temperature
            )
        }
    }

    nonisolated static func formatted(_ value: Double, unit: String) -> String {
        "\(Int(value.rounded()))\(unit)"
    }
}
