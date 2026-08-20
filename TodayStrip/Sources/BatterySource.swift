import Foundation
import IOKit.ps
import Observation

/// Battery level from IOKit's power source registry.
///
/// Polled rather than notification-driven: charge moves on the order of minutes, and a 30-second
/// poll is a fraction of the code (and none of the C-callback bridging) of `IOPSNotification`.
/// Machines without a battery publish `nil` forever, which drops the module out of the rotation.
@Observable
final class BatterySource: StripSource {
    nonisolated struct State: Equatable, Sendable {
        var percentage: Int
        var isCharging: Bool
        var isPluggedIn: Bool
        /// Seconds until empty or full, when the system is willing to estimate.
        var timeRemaining: TimeInterval?
    }

    let kind = StripItemKind.battery

    @ObservationIgnored var onChange: (() -> Void)?
    private(set) var currentItem: StripItem?
    private(set) var state: State?

    private var poller: Timer?

    func start() {
        refresh()
        guard poller == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        poller = timer
    }

    func stop() {
        poller?.invalidate()
        poller = nil
    }

    func refresh() {
        state = Self.readState()
        publish()
    }

    // MARK: - Reading IOKit

    private nonisolated static func readState() -> State? {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]

        for source in list {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            guard let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0
            else { continue }

            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let isPluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue

            // Negative values are the "unknown" and "unlimited" sentinels, not real estimates.
            let estimate = IOPSGetTimeRemainingEstimate()
            let timeRemaining = estimate > 0 ? estimate : nil

            return State(
                percentage: Int((Double(current) / Double(maximum) * 100).rounded()),
                isCharging: isCharging,
                isPluggedIn: isPluggedIn,
                timeRemaining: timeRemaining
            )
        }
        return nil
    }

    // MARK: - Publishing

    private func publish() {
        guard let state else {
            setItem(nil)
            return
        }

        let draining = !state.isPluggedIn
        let priority: StripPriority
        let tint: StripTint
        switch state.percentage {
        case ..<10 where draining:
            priority = .urgent
            tint = .critical
        case ..<20 where draining:
            priority = .elevated
            tint = .warning
        default:
            priority = .ambient
            tint = .normal
        }

        var text = "\(state.percentage)%"
        if let remaining = state.timeRemaining, draining, state.percentage < 40 {
            text += " · \(Self.shortDuration(remaining))"
        }

        setItem(
            StripItem(
                kind: .battery,
                priority: priority,
                symbolName: Self.symbol(for: state),
                text: text,
                compactText: "\(state.percentage)%",
                tint: tint
            )
        )
    }

    private func setItem(_ item: StripItem?) {
        guard item != currentItem else { return }
        currentItem = item
        onChange?()
    }

    // MARK: - Presentation

    nonisolated static func symbol(for state: State) -> String {
        if state.isCharging { return "battery.100percent.bolt" }
        switch state.percentage {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    nonisolated static func shortDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        return minutes >= 60
            ? String(format: "%d:%02dh", minutes / 60, minutes % 60)
            : "\(minutes)m"
    }
}
