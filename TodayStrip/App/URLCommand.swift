import Foundation

/// Something the app can be asked to do from outside: a `todaystrip://` URL, or a global hotkey.
///
/// Both entry points funnel through this one type, so a hotkey and a URL cannot drift apart in
/// what they mean — and so the parsing, which is where mistakes hide, is a pure function.
nonisolated enum URLCommand: Equatable, Sendable {
    case startCountdown(minutes: Int)
    case startStopwatch
    case stopTimer
    case setNote(String)
    case openPanel

    static let scheme = "todaystrip"

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }

        // In `todaystrip://timer/25` the command is the host and the argument is the path.
        let command = (url.host() ?? "").lowercased()
        let argument = url.pathComponents.first { $0 != "/" }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        switch command {
        case "timer":
            if argument?.lowercased() == "stop" {
                self = .stopTimer
                return
            }
            let raw = argument ?? query.first { $0.name == "minutes" }?.value
            guard let raw, let minutes = Int(raw), minutes > 0 else { return nil }
            self = .startCountdown(minutes: minutes)

        case "stopwatch":
            self = .startStopwatch

        case "note":
            let text = (query.first { $0.name == "text" }?.value ?? "").trimmed
            guard !text.isEmpty else { return nil }
            self = .setNote(text)

        case "open":
            self = .openPanel

        default:
            return nil
        }
    }
}
