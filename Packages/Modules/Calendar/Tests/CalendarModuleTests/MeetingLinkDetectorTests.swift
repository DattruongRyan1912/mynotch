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
        ("https://acme.zoom.us/j/81234567890?pwd=ab%2Bcd", .zoom),
        ("https://acme.zoom.us/j/81234567890?pwd=ab+cd", .zoom),
        ("https://acme.eu.zoom.us/j/81234567890", .zoom),
        ("https://acme.webex.com/acme/j.php?MTID=m1234abcd", .webex),
        ("https://acme.my.webex.com/meet/ryan", .webex),
        ("https://facetime.apple.com/join#v=1&p=AbCdEf123&k=XyZ", .faceTime),
        ("https://whereby.com/acme-standup", .whereby),
        ("https://acme.whereby.com/standup", .whereby),
        ("https://whereby.com/acme-standup?roomKey=ZXlKaGJHY2lPaUpTVXpJMU5pSjk.Ab-c_D", .whereby),
        ("https://meet.jit.si/WeeklyStandup2026", .jitsi),
        ("https://meet.jit.si/WeeklyStandup2026#config.prejoinPageEnabled=false&userInfo.displayName=%22Ryan%22", .jitsi),
        ("https://meet.jit.si/weekly-standup?jwt=eyJhbGciOiJIUzI1NiJ9.e30.Zm9v", .jitsi),
        ("https://jitsi.acme.example/WeeklyStandup", .jitsi),
        ("https://meet.jitsi.acme.example:8443/WeeklyStandup?lang=vi", .jitsi),
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

    // MARK: Whereby and Jitsi

    @Test func wherebyAndJitsiHostsMatchInAnyCase() {
        #expect(link(in: "https://Meet.Jit.Si/WeeklyStandup")?.provider == .jitsi)
        #expect(link(in: "HTTPS://ACME.WHEREBY.COM/standup")?.provider == .whereby)
        #expect(link(in: "https://JITSI.acme.example/Standup")?.provider == .jitsi)
    }

    @Test func trailingPunctuationIsStrippedFromWherebyAndJitsiLinks() {
        #expect(link(in: "Join at (https://whereby.com/acme-standup).")?.url == URL(string: "https://whereby.com/acme-standup"))
        #expect(link(in: "Join <https://meet.jit.si/WeeklyStandup>,")?.url == URL(string: "https://meet.jit.si/WeeklyStandup"))
        #expect(link(in: #"<a href="https://meet.jit.si/WeeklyStandup">Join</a>"#)?.url == URL(string: "https://meet.jit.si/WeeklyStandup"))
    }

    @Test func wherebyNeedsARoom() {
        #expect(link(in: "https://whereby.com/") == nil)
        #expect(link(in: "https://whereby.com") == nil)
        #expect(link(in: "https://notwhereby.com/acme-standup") == nil)
        #expect(link(in: "https://whereby.com.evil.example/acme-standup") == nil)
        #expect(link(in: "whereby.com/acme-standup") == nil)
    }

    @Test func publicJitsiNeedsARoom() {
        #expect(link(in: "https://meet.jit.si/") == nil)
        #expect(link(in: "https://meet.jit.si") == nil)
        #expect(link(in: "https://notmeet.jit.si.evil.example/WeeklyStandup") == nil)
        #expect(link(in: "meet.jit.si/WeeklyStandup") == nil)
    }

    @Test func aServerOfOneOwnIsJitsiOnlyWhenTheHostSaysSo() {
        #expect(link(in: "Room: https://meet.acme.example/WeeklyStandup") == nil)
        #expect(link(in: "Room: https://acme.example/WeeklyStandup") == nil)
        #expect(link(in: "Room: https://jitsi.acme.example/WeeklyStandup") == MeetingLink(provider: .jitsi, url: URL(string: "https://jitsi.acme.example/WeeklyStandup")!))
        #expect(MeetingLinkDetector.detect(url: URL(string: "https://meet.jitsi.acme.example/WeeklyStandup"), location: nil, notes: nil)?.provider == .jitsi)
        #expect(MeetingLinkDetector.detect(url: URL(string: "https://meet.acme.example/WeeklyStandup"), location: nil, notes: nil) == nil)
    }

    @Test func aServerOfOneOwnIsJitsiWhenTheNotesSaySoBeforeTheLink() {
        let room = URL(string: "https://meet.acme.example/WeeklyStandup")!
        #expect(link(in: "Jitsi: https://meet.acme.example/WeeklyStandup") == MeetingLink(provider: .jitsi, url: room))
        #expect(link(in: "Join via JITSI Meet at https://meet.acme.example/WeeklyStandup.") == MeetingLink(provider: .jitsi, url: room))
        #expect(link(in: "Jitsi Meet\nhttps://meet.acme.example/WeeklyStandup") == MeetingLink(provider: .jitsi, url: room))
        #expect(MeetingLinkDetector.detect(url: nil, location: "Jitsi https://meet.acme.example/WeeklyStandup", notes: nil)?.url == room)
    }

    @Test func theWordJitsiMustBeNearTheLink() {
        // After the link, or lines away from it, it says nothing about this address.
        #expect(link(in: "https://meet.acme.example/WeeklyStandup (Jitsi)") == nil)
        #expect(link(in: "Jitsi\n\nAgenda to follow.\nhttps://meet.acme.example/WeeklyStandup") == nil)
        #expect(link(in: "Same as last week https://meet.acme.example/WeeklyStandup") == nil)
    }

    @Test func anotherLinkInTheNotesIsNotTakenForTheJitsiRoom() {
        let room = URL(string: "https://meet.acme.example/WeeklyStandup")!
        #expect(link(in: "Agenda: https://docs.acme.example/agenda\nJitsi: https://meet.acme.example/WeeklyStandup")?.url == room)
        #expect(link(in: "Jitsi: https://meet.acme.example/WeeklyStandup, agenda https://docs.acme.example/agenda")?.url == room)
        // The word belongs to the first link that follows it only.
        #expect(link(in: "Jitsi: https://meet.acme.example/WeeklyStandup https://docs.acme.example/agenda")?.url == room)
        #expect(link(in: "Agenda https://docs.acme.example/agenda\nJitsi: see you") == nil)
        // The word is used up by the first address after it, even when that one is not a room.
        #expect(link(in: "Jitsi docs: https://docs.acme.example/a/b see also https://meet.acme.example/WeeklyStandup") == nil)
    }

    @Test func aServerOfOneOwnNeedsASingleRoomName() {
        #expect(link(in: "Jitsi: https://meet.acme.example/") == nil)
        #expect(link(in: "Jitsi: https://meet.acme.example") == nil)
        #expect(link(in: "Jitsi: https://meet.acme.example/team/WeeklyStandup") == nil)
        #expect(link(in: "Jitsi: https://meet.acme.example/WeeklyStandup/") == nil)
        #expect(link(in: "Jitsi: https://meet.acme.example/report.pdf") == nil)
        #expect(link(in: "Jitsi: http://meet.acme.example/WeeklyStandup") == nil)
        #expect(link(in: "Jitsi: https://meet.acme.example/WeeklyStandup?lang=vi")?.url == URL(string: "https://meet.acme.example/WeeklyStandup?lang=vi"))
    }

    @Test func theJitsiProjectsOwnSitesAreNotRooms() {
        #expect(link(in: "https://jitsi.org/downloads") == nil)
        #expect(link(in: "Jitsi: https://jitsi.org/downloads") == nil)
        #expect(link(in: "https://community.jitsi.org/t/how-to-host/12345") == nil)
        #expect(link(in: "Jitsi: https://community.jitsi.org/latest") == nil)
        #expect(link(in: "https://jitsi.github.io/handbook/docs/intro") == nil)
    }

    @Test func theFirstLinkInAFieldWinsAmongTheNewServicesToo() {
        let jitsi = "https://meet.jit.si/WeeklyStandup"
        let whereby = "https://acme.whereby.com/standup"
        #expect(link(in: "Main \(whereby) or backup \(jitsi)")?.provider == .whereby)
        #expect(link(in: "Main \(jitsi) or backup \(whereby)")?.provider == .jitsi)
        #expect(link(in: "Main https://zoom.us/j/123 or Jitsi: https://meet.acme.example/WeeklyStandup")?.provider == .zoom)
        #expect(link(in: "Jitsi: https://meet.acme.example/WeeklyStandup or https://zoom.us/j/123")?.provider == .jitsi)
    }

    @Test func urlBeatsLocationBeatsNotesForTheNewServices() {
        let whereby = "https://acme.whereby.com/standup"
        let jitsi = "https://meet.jit.si/WeeklyStandup"
        #expect(MeetingLinkDetector.detect(url: URL(string: whereby), location: jitsi, notes: "https://zoom.us/j/111")?.provider == .whereby)
        #expect(MeetingLinkDetector.detect(url: nil, location: jitsi, notes: whereby)?.provider == .jitsi)
        #expect(MeetingLinkDetector.detect(url: URL(string: "https://example.com/agenda"), location: "Room 4", notes: whereby)?.provider == .whereby)
    }

    // MARK: Line endings

    /// Invites that come by mail or from an .ics file end their lines with CRLF, or with a bare CR or a Unicode
    /// separator; "the line above" must mean the same thing for all of them.
    nonisolated static let lineEndings = ["\n", "\r\n", "\r", "\u{2028}", "\u{2029}", "\u{85}"]

    @Test(arguments: lineEndings)
    func theWordJitsiOnTheLineAboveCountsWhateverTheLineEnding(_ eol: String) {
        let room = URL(string: "https://meet.acme.example/WeeklyStandup")!
        #expect(link(in: "Jitsi Meet\(eol)https://meet.acme.example/WeeklyStandup") == MeetingLink(provider: .jitsi, url: room))
        #expect(link(in: "Agenda\(eol)Jitsi\(eol)https://meet.acme.example/WeeklyStandup") == MeetingLink(provider: .jitsi, url: room))
    }

    @Test(arguments: lineEndings)
    func theWordJitsiFurtherUpDoesNotCountWhateverTheLineEnding(_ eol: String) {
        let notes = ["Jitsi migration plan", "", "Lots of text", "more text", "https://docs.acme.example/plan"]
        #expect(link(in: notes.joined(separator: eol)) == nil)
        // Two lines above is already too far, and so is the whole text being one line.
        #expect(link(in: ["Jitsi", "Agenda to follow.", "https://meet.acme.example/WeeklyStandup"].joined(separator: eol)) == nil)
        #expect(link(in: "Jitsi\(eol)\(eol)Agenda to follow.\(eol)https://meet.acme.example/WeeklyStandup") == nil)
    }

    // MARK: Room URLs only

    @Test func onlyRoomsOfWherebyAndPublicJitsiAreLinks() {
        for page in [
            "https://support.whereby.com/hc/en-us/articles/123",
            "https://whereby.com/information/terms",
            "https://docs.whereby.com/reference",
            "https://help.whereby.com/start",
            "https://www.whereby.com/pricing",
            "https://whereby.com/robots.txt",
            "https://meet.jit.si/static/close3.html",
            "https://meet.jit.si/images/favicon.ico",
        ] {
            #expect(link(in: "See \(page) for details") == nil, "\(page)")
        }
    }

    @Test func aRoomStopsAtTheEndOfItsAddress() {
        #expect(link(in: "'https://whereby.com/acme-standup'")?.url == URL(string: "https://whereby.com/acme-standup"))
        #expect(link(in: "\"https://meet.jit.si/WeeklyStandup\"")?.url == URL(string: "https://meet.jit.si/WeeklyStandup"))
        #expect(link(in: "Join at https://meet.jit.si/WeeklyStandup.")?.url == URL(string: "https://meet.jit.si/WeeklyStandup"))
        #expect(link(in: "Join at https://whereby.com/acme-standup/ now")?.url == URL(string: "https://whereby.com/acme-standup"))
        #expect(link(in: "Join at https://whereby.com/acme-standup?roomKey=abc.def-ghi.")?.url == URL(string: "https://whereby.com/acme-standup?roomKey=abc.def-ghi"))
    }

    // MARK: Rooms on a server of one's own look like rooms

    @Test func aRoomOnAServerOfOneOwnIsANameNotAPage() {
        #expect(link(in: "Jitsi: https://meet.acme.example/ab") == nil)
        #expect(link(in: "Jitsi: https://meet.acme.example/abc")?.provider == .jitsi)
        #expect(link(in: "https://jitsi.github.io/handbook") == nil)
        #expect(link(in: "Jitsi: https://acme.github.io/handbook") == nil)
        #expect(link(in: "Jitsi: https://acme.gitlab.io/handbook") == nil)
    }
}
