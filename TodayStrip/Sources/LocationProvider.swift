import Foundation
import CoreLocation
import Observation
import os

/// Coarse location for the weather module.
///
/// Asks for kilometre accuracy and a single fix rather than continuous updates: weather does not
/// change between one end of a city and the other, and a one-shot request keeps the location
/// indicator from sitting in the menu bar. Delegate callbacks are `nonisolated` and immediately
/// reduce `CLLocation` to two `Double`s before hopping to the main actor.
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    nonisolated struct Coordinate: Equatable, Sendable {
        var latitude: Double
        var longitude: Double
    }

    nonisolated enum Status: Equatable, Sendable {
        case unknown
        case denied
        case located(Coordinate)
        case failed(String)
    }

    private nonisolated static let log = Logger(subsystem: Logger.subsystem, category: "Location")

    private(set) var status: Status = .unknown
    @ObservationIgnored var onChange: ((Status) -> Void)?

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var coordinate: Coordinate? {
        if case .located(let coordinate) = status { return coordinate }
        return nil
    }

    /// Requests authorization if needed, then a single fix.
    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            update(.denied)
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        @unknown default:
            manager.requestLocation()
        }
    }

    private func update(_ status: Status) {
        guard status != self.status else { return }
        self.status = status
        onChange?(status)
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let authorization = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch authorization {
            case .authorized, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                self.update(.denied)
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let coordinate = Coordinate(
            latitude: last.coordinate.latitude,
            longitude: last.coordinate.longitude
        )
        Task { @MainActor [weak self] in
            self?.update(.located(coordinate))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Self.log.error("Location request failed: \(message)")
        Task { @MainActor [weak self] in
            // A failure with a fix already in hand is not worth downgrading the UI for.
            guard self?.coordinate == nil else { return }
            self?.update(.failed(message))
        }
    }
}
