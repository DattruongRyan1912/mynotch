import Foundation
import Testing
@testable import CalendarModule

@Suite struct MeetingLinkDetectorTests {
    func link(in notes: String) -> MeetingLink? {
        MeetingLinkDetector.detect(url: nil, location: nil, notes: notes)
    }

    @Test(arguments: [
        ("https://us02web.zoom.us/j/81234567890?pwd=AbC123.1", MeetingProvider.zoom),
        ("https://zoom.us/my/ryan.truong", .zoom),
        ("https://acme.zoom.us/w/81234567890?tk=x-y_z", .zoom),
        ("https://agency.zoomgov.com/j/1601234567", .zoom),
        ("https://zoomgov.us/j/1601234567", .zoom),
        ("https://meet.google.com/abc-defg-hij", .googleMeet),
        ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_NjQ%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d", .teams),
        ("https://teams.live.com/meet/9876543210", .teams),
        ("https://acme.webex.com/acme/j.php?MTID=m1234abcd", .webex),
        ("https://facetime.apple.com/join#v=1&p=AbCdEf123&k=XyZ", .faceTime),
    ])
    func detectsEachProvider(url: String, provider: MeetingProvider) {
        #expect(link(in: "Join: \(url) see you") == MeetingLink(provider: provider, url: URL(string: url)!))
    }

    @Test func urlBeatsLocationBeatsNotes() {
        let zoom = "https://zoom.us/j/111"
        let meet = "https://meet.google.com/abc-defg-hij"
        let teams = "https://teams.live.com/meet/222"
        #expect(MeetingLinkDetector.detect(url: URL(string: zoom), location: meet, notes: teams)?.url == URL(string: zoom))
        #expect(MeetingLinkDetector.detect(url: nil, location: "Room 4 / \(meet)", notes: teams)?.url == URL(string: meet))
        #expect(MeetingLinkDetector.detect(url: URL(string: "https://example.com/agenda"), location: "Room 4", notes: teams)?.url == URL(string: teams))
    }

    @Test func firstLinkInAFieldWins() {
        let found = link(in: "Backup https://meet.google.com/abc-defg-hij or main https://zoom.us/j/123")
        #expect(found == MeetingLink(provider: .googleMeet, url: URL(string: "https://meet.google.com/abc-defg-hij")!))
    }

    @Test func trailingPunctuationIsStripped() {
        #expect(link(in: "Join at https://zoom.us/j/123456789.")?.url == URL(string: "https://zoom.us/j/123456789"))
        #expect(link(in: "Join <https://teams.microsoft.com/l/meetup-join/abc>")?.url == URL(string: "https://teams.microsoft.com/l/meetup-join/abc"))
        #expect(link(in: "(https://acme.webex.com/meet/ryan);")?.url == URL(string: "https://acme.webex.com/meet/ryan"))
        #expect(link(in: "[https://facetime.apple.com/join#v=1&p=abc],")?.url == URL(string: "https://facetime.apple.com/join#v=1&p=abc"))
    }

    @Test func linksEndAtCharactersURLsCannotContain() {
        let html = #"<a href="https://teams.microsoft.com/l/meetup-join/abc">Join</a>"#
        #expect(link(in: html)?.url == URL(string: "https://teams.microsoft.com/l/meetup-join/abc"))
    }

    @Test func hostsMatchInAnyCase() {
        #expect(link(in: "https://Meet.Google.com/abc-defg-hij") == MeetingLink(provider: .googleMeet, url: URL(string: "https://Meet.Google.com/abc-defg-hij")!))
        #expect(link(in: "HTTPS://US02WEB.ZOOM.US/j/123")?.provider == .zoom)
        #expect(link(in: "https://Teams.Microsoft.com/l/meetup-join/abc")?.provider == .teams)
    }

    @Test func returnsNilWithoutAMeetingLink() {
        #expect(MeetingLinkDetector.detect(url: nil, location: nil, notes: nil) == nil)
        #expect(MeetingLinkDetector.detect(url: URL(string: "https://example.com/meeting"), location: "Room 4B", notes: "Bring slides") == nil)
        #expect(link(in: "https://zoom.us/") == nil)
        #expect(link(in: "meet.google.com/abc-defg-hij") == nil)
        #expect(link(in: "https://meet.google.com/landing") == nil)
        #expect(link(in: "https://notzoom.example.com/j/123") == nil)
    }
}
