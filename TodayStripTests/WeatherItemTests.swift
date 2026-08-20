import Foundation
import Testing
@testable import TodayStrip

@Suite("Weather strip item")
struct WeatherItemTests {
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

    @Test func leadsWithComingRainRatherThanTemperature() {
        let item = WeatherSource.item(for: conditions(forecast: [(30, 0.8)]), now: now)
        #expect(item.text == "Rain in 30m")
        #expect(item.symbolName == "cloud.rain.fill")
    }

    /// Coming rain should be seen before it starts, so it outranks the ambient readings.
    @Test func comingRainOutranksAmbientItems() {
        let item = WeatherSource.item(for: conditions(forecast: [(30, 0.8)]), now: now)
        #expect(item.priority > .ambient)
    }

    @Test func reportsFrostWithTheLow() {
        let item = WeatherSource.item(for: conditions(low: -2), now: now)
        #expect(item.text == "Frost tonight, -2°C")
    }

    @Test func plainConditionsStayAmbient() {
        let item = WeatherSource.item(for: conditions(), now: now)
        #expect(item.text == "16°C Clear")
        #expect(item.priority == .ambient)
    }

    @Test func theCompactFormAlwaysFitsTheMenuBar() {
        let cases = [
            conditions(forecast: [(30, 0.8)]),
            conditions(precipitationNow: 0.6),
            conditions(low: -2),
            conditions(),
        ]
        for condition in cases {
            let item = WeatherSource.item(for: condition, now: now)
            #expect((item.compactText ?? item.text).count <= 12)
        }
    }
}
