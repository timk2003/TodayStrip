import Foundation

/// The most useful thing to say about the weather right now.
///
/// The point of the weather module is not to report the temperature — that is decoration, and the
/// strip has no room for decoration. It is to report the thing that changes what you do: rain
/// about to start, frost tonight. When nothing is about to change, it falls back to plain
/// conditions and takes its turn quietly.
nonisolated enum WeatherHeadline: Equatable, Sendable {
    /// Rain begins within the forecast horizon.
    case rainStarting(inMinutes: Int)
    /// It is raining at this moment.
    case rainingNow
    /// Today's low is at or below freezing.
    case frostTonight(low: Double)
    /// Nothing notable: temperature and description.
    case conditions

    /// Readings below this are drizzle traces the forecast is not confident about, and not worth
    /// taking a menu bar slot for.
    static let minimumPrecipitation = 0.1

    /// Rain further out than this is not actionable yet.
    static let horizon: TimeInterval = 90 * 60

    static func of(_ conditions: OpenMeteo.Conditions, now: Date = Date()) -> WeatherHeadline {
        if conditions.precipitationNow >= minimumPrecipitation {
            return .rainingNow
        }

        let upcoming = conditions.precipitation.first { sample in
            sample.time > now
                && sample.time.timeIntervalSince(now) <= horizon
                && sample.millimetres >= minimumPrecipitation
        }
        if let upcoming {
            return .rainStarting(inMinutes: Int((upcoming.time.timeIntervalSince(now) / 60).rounded()))
        }

        if let low = conditions.low, low <= 0 {
            return .frostTonight(low: low)
        }

        return .conditions
    }
}
