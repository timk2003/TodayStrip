import Foundation
import Testing
@testable import TodayStrip

@Suite("Meeting link detection")
struct MeetingLinkTests {
    @Test func recognisesZoomInTheLocationField() {
        let link = MeetingLink.detect(url: nil, location: "https://acme.zoom.us/j/9876543210", notes: nil)
        #expect(link?.service == .zoom)
    }

    @Test func recognisesGoogleMeetBuriedInNotes() {
        let notes = """
        Agenda attached.
        Join: https://meet.google.com/abc-defg-hij
        Dial-in also available.
        """
        #expect(MeetingLink.detect(url: nil, location: nil, notes: notes)?.service == .meet)
    }

    /// A known service anywhere beats an unknown link in a higher-confidence field.
    @Test func prefersAKnownServiceOverAnUnknownLink() {
        let link = MeetingLink.detect(
            url: nil,
            location: "https://example.com/room",
            notes: "https://teams.microsoft.com/l/meetup-join/xyz"
        )
        #expect(link?.service == .teams)
    }

    @Test func acceptsAnUnknownHostFromTheLocationField() {
        let link = MeetingLink.detect(url: nil, location: "https://call.acme.io/standup", notes: nil)
        #expect(link?.service == .generic)
    }

    /// Notes are full of documents and signatures; an unknown link there is not a meeting.
    @Test func ignoresAnUnknownLinkFoundOnlyInNotes() {
        let link = MeetingLink.detect(url: nil, location: nil, notes: "Docs: https://example.com/spec")
        #expect(link == nil)
    }

    @Test func ignoresNonWebSchemes() {
        let link = MeetingLink.detect(url: URL(string: "tel:+4912345"), location: nil, notes: nil)
        #expect(link == nil)
    }

    @Test func findsNothingInEmptyFields() {
        #expect(MeetingLink.detect(url: nil, location: "", notes: "") == nil)
    }
}
