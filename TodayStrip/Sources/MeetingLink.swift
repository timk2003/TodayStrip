import Foundation

/// A join link recognised in an event's location, URL or notes.
///
/// Detection runs through `NSDataDetector` rather than a URL regex, so it copes with the way
/// calendar invitations bury links in prose, then classifies by host. Unknown hosts still count
/// as joinable when they came from the event's dedicated URL or location field, where a link is
/// there for exactly one reason.
nonisolated struct MeetingLink: Equatable, Sendable {
    nonisolated enum Service: String, Sendable {
        case zoom, meet, teams, webex, whereby, jitsi, slack, discord, generic

        var title: String {
            switch self {
            case .zoom: "Zoom"
            case .meet: "Google Meet"
            case .teams: "Microsoft Teams"
            case .webex: "Webex"
            case .whereby: "Whereby"
            case .jitsi: "Jitsi"
            case .slack: "Slack"
            case .discord: "Discord"
            case .generic: "Meeting"
            }
        }

        var symbol: String {
            switch self {
            case .generic: "link"
            default: "video.fill"
            }
        }
    }

    var url: URL
    var service: Service

    var title: String { service.title }
    var symbol: String { service.symbol }

    /// Searches the fields in confidence order: a link in `url` or `location` is almost always
    /// the meeting, whereas notes may also contain agendas, docs and signatures.
    static func detect(url: URL?, location: String?, notes: String?) -> MeetingLink? {
        if let url, let link = classify(url), link.service != .generic {
            return link
        }
        if let location, let link = firstLink(in: location, acceptGeneric: true) {
            return link
        }
        if let url, let link = classify(url) {
            return link
        }
        if let notes, let link = firstLink(in: notes, acceptGeneric: false) {
            return link
        }
        return nil
    }

    private static func firstLink(in text: String, acceptGeneric: Bool) -> MeetingLink? {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var fallback: MeetingLink?

        for match in detector.matches(in: text, range: range) {
            guard let url = match.url, let link = classify(url) else { continue }
            if link.service != .generic { return link }
            if fallback == nil { fallback = link }
        }
        return acceptGeneric ? fallback : nil
    }

    private static func classify(_ url: URL) -> MeetingLink? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        let host = (url.host()?.lowercased()) ?? ""
        let service: Service

        switch true {
        case host.contains("zoom.us"), host.contains("zoom.com"): service = .zoom
        case host.contains("meet.google.com"): service = .meet
        case host.contains("teams.microsoft.com"), host.contains("teams.live.com"): service = .teams
        case host.contains("webex.com"): service = .webex
        case host.contains("whereby.com"): service = .whereby
        case host.contains("meet.jit.si"), host.contains("jitsi"): service = .jitsi
        case host.contains("slack.com"): service = .slack
        case host.contains("discord.com"), host.contains("discord.gg"): service = .discord
        default: service = .generic
        }
        return MeetingLink(url: url, service: service)
    }
}
