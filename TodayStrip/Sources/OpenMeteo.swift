import Foundation

/// Minimal client for the Open-Meteo API.
///
/// Chosen over WeatherKit because it needs no account, no key and no entitlement, so anyone who
/// clones this repository can build and run the app as-is. Non-commercial use is free; see
/// https://open-meteo.com/en/terms.
nonisolated enum OpenMeteo {
    nonisolated enum Failure: LocalizedError {
        case badResponse(Int)
        case noResults

        var errorDescription: String? {
            switch self {
            case .badResponse(let code): "Weather service returned status \(code)."
            case .noResults: "No matching place found."
            }
        }
    }

    // MARK: - Current conditions

    nonisolated struct Conditions: Equatable, Sendable {
        var temperature: Double
        var apparentTemperature: Double
        var high: Double?
        var low: Double?
        var code: Int
        var isDay: Bool
        var unitSymbol: String
        var fetched: Date
    }

    static func conditions(
        latitude: Double,
        longitude: Double,
        unit: TemperatureUnit,
        session: URLSession = .shared
    ) async throws -> Conditions {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        var query: [URLQueryItem] = [
            .init(name: "latitude", value: String(format: "%.4f", latitude)),
            .init(name: "longitude", value: String(format: "%.4f", longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "timezone", value: "auto"),
        ]
        if let apiUnit = unit.apiValue {
            query.append(.init(name: "temperature_unit", value: apiUnit))
        }
        components.queryItems = query

        let payload: ForecastPayload = try await get(components.url!, session: session)
        return Conditions(
            temperature: payload.current.temperature2m,
            apparentTemperature: payload.current.apparentTemperature ?? payload.current.temperature2m,
            high: payload.daily?.temperature2mMax.first,
            low: payload.daily?.temperature2mMin.first,
            code: payload.current.weatherCode,
            isDay: payload.current.isDay == 1,
            unitSymbol: unit.symbol,
            fetched: Date()
        )
    }

    // MARK: - Geocoding

    static func search(
        place name: String,
        session: URLSession = .shared
    ) async throws -> [Place] {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            .init(name: "name", value: trimmed),
            .init(name: "count", value: "8"),
            .init(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en"),
            .init(name: "format", value: "json"),
        ]

        let payload: GeocodingPayload = try await get(components.url!, session: session)
        return (payload.results ?? []).map {
            Place(
                name: $0.name,
                admin: $0.admin1,
                country: $0.country,
                latitude: $0.latitude,
                longitude: $0.longitude
            )
        }
    }

    // MARK: - Transport

    private static func get<T: Decodable>(_ url: URL, session: URLSession) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadRevalidatingCacheData

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.badResponse(http.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Wire format

    private nonisolated struct ForecastPayload: Decodable {
        struct Current: Decodable {
            let temperature2m: Double
            let apparentTemperature: Double?
            let weatherCode: Int
            let isDay: Int
        }

        struct Daily: Decodable {
            let temperature2mMax: [Double]
            let temperature2mMin: [Double]
        }

        let current: Current
        let daily: Daily?
    }

    private nonisolated struct GeocodingPayload: Decodable {
        struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let admin1: String?
        }

        let results: [Result]?
    }
}

/// WMO weather interpretation codes, as returned by Open-Meteo.
///
/// The service reports a number; this turns it into the two things the UI needs. Day and night
/// get different symbols so a clear night doesn't show a sun in the menu bar.
nonisolated enum WeatherCode {
    static func description(_ code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mainly clear"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55: "Drizzle"
        case 56, 57: "Freezing drizzle"
        case 61, 63: "Rain"
        case 65: "Heavy rain"
        case 66, 67: "Freezing rain"
        case 71, 73: "Snow"
        case 75: "Heavy snow"
        case 77: "Snow grains"
        case 80, 81: "Rain showers"
        case 82: "Heavy showers"
        case 85, 86: "Snow showers"
        case 95: "Thunderstorm"
        case 96, 99: "Thunderstorm with hail"
        default: "Unknown"
        }
    }

    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1: isDay ? "sun.min.fill" : "moon.fill"
        case 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55: "cloud.drizzle.fill"
        case 56, 57: "cloud.sleet.fill"
        case 61, 63: "cloud.rain.fill"
        case 65: "cloud.heavyrain.fill"
        case 66, 67: "cloud.sleet.fill"
        case 71, 73, 75, 77: "cloud.snow.fill"
        case 80, 81: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 82: "cloud.heavyrain.fill"
        case 85, 86: "cloud.snow.fill"
        case 95: "cloud.bolt.fill"
        case 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}
