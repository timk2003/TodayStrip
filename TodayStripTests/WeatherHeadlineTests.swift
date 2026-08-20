import Foundation
import Testing
@testable import TodayStrip

@Suite("Weather headline")
struct WeatherHeadlineTests {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    private func conditions(
        temperature: Double = 16,
        precipitationNow: Double = 0,
        low: Double? = 12,
        code: Int = 0,
        forecast: [(minutes: Int, millimetres: Double)] = []
    ) -> OpenMeteo.Conditions {
        OpenMeteo.Conditions(
            temperature: temperature,
            apparentTemperature: temperature,
            precipitationNow: precipitationNow,
            high: 20,
            low: low,
            code: code,
            isDay: true,
            unitSymbol: "°C",
            precipitation: forecast.map {
                OpenMeteo.PrecipitationSample(
                    time: now.addingTimeInterval(TimeInterval($0.minutes) * 60),
                    millimetres: $0.millimetres
                )
            },
            fetched: now
        )
    }

    @Test func announcesRainThatStartsSoon() {
        let headline = WeatherHeadline.of(
            conditions(forecast: [(15, 0), (30, 0.4), (45, 0.8)]),
            now: now
        )
        #expect(headline == .rainStarting(inMinutes: 30))
    }

    @Test func saysItIsRainingWhenItAlreadyIs() {
        let headline = WeatherHeadline.of(
            conditions(precipitationNow: 0.6, forecast: [(15, 0.5)]),
            now: now
        )
        #expect(headline == .rainingNow)
    }

    /// A trace reading is not weather worth a menu bar slot.
    @Test func ignoresPrecipitationBelowTheThreshold() {
        let headline = WeatherHeadline.of(
            conditions(forecast: [(15, 0.05), (30, 0.02)]),
            now: now
        )
        #expect(headline == .conditions)
    }

    @Test func ignoresRainBeyondTheForecastHorizon() {
        let headline = WeatherHeadline.of(
            conditions(forecast: [(150, 2.0)]),
            now: now
        )
        #expect(headline == .conditions)
    }

    @Test func warnsAboutFrostWhenNoRainIsComing() {
        let headline = WeatherHeadline.of(conditions(low: -2), now: now)
        #expect(headline == .frostTonight(low: -2))
    }

    /// Rain is actionable in the next hour; frost is not until tonight.
    @Test func rainOutranksFrost() {
        let headline = WeatherHeadline.of(
            conditions(low: -2, forecast: [(30, 0.8)]),
            now: now
        )
        #expect(headline == .rainStarting(inMinutes: 30))
    }

    @Test func fallsBackToPlainConditions() {
        #expect(WeatherHeadline.of(conditions(), now: now) == .conditions)
    }

    @Test func ignoresSamplesAlreadyInThePast() {
        let headline = WeatherHeadline.of(
            conditions(forecast: [(-30, 2.0), (-15, 2.0)]),
            now: now
        )
        #expect(headline == .conditions)
    }
}
