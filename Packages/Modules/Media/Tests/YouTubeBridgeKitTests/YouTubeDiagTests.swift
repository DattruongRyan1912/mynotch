import Foundation
import Testing
@testable import YouTubeBridgeKit

@Suite struct YouTubeDiagTests {
    /// Every event of the protocol's table, with the part that sends it.
    static let allowed: [(String, String)] = [
        ("sw", "sw-start v=0.1.1"), ("sw", "sw-start v=unknown"), ("sw", "sw-start v=12"),
        ("sw", "sw-msg playback"), ("sw", "sw-msg clear"), ("sw", "sw-msg captions events=130"),
        ("sw", "sw-reject untrusted"), ("sw", "sw-reject invalid captions"), ("sw", "sw-reject invalid playback"),
        ("sw", "sw-reject invalid clear"), ("sw", "sw-reject invalid diag"), ("sw", "sw-reject invalid unknown"),
        ("sw", "sw-reconnect after=host-not-found failures=3"), ("sw", "sw-reconnect after=disconnected failures=120"),
        ("sw", "sw-inject tabs=3 injected=2 failed=1"), ("sw", "sw-inject tabs=0 injected=0 failed=0"),
        ("sw", "sw-inject tabs=999999 injected=999999 failed=0"),
        ("sw", "sw-access youtube=granted"), ("sw", "sw-access youtube=withheld"),
        ("content", "content-start"), ("content", "content-no-lib"), ("content", "content-video-found"), ("content", "content-video-missing"),
        ("content", "content-cc on"), ("content", "content-cc off"),
        ("content", "content-send-error no-receiving-end count=2"), ("content", "content-send-error context-invalidated count=100000"),
        ("content", "content-alive videoid-present=true playing=false"),
        ("content", "content-tick-error type-error"),
        ("page", "page-wrap fetch=true xhr=false"), ("page", "page-wrap-check fetch=false xhr=false"),
        ("page", "page-seen fetch"), ("page", "page-seen xhr"),
        ("page", "page-timedtext json3 events=3"), ("page", "page-timedtext srv3 events=1"), ("page", "page-timedtext other events=0"),
        ("page", "page-timedtext-status 404"), ("page", "page-timedtext-failed fetch"), ("page", "page-timedtext-failed xhr"),
        ("page", "page-timedtext-parse-error"), ("page", "page-timedtext-too-large"),
    ]

    static func message(where origin: Any, event: Any) -> [String: Any] {
        ["v": 1, "type": "diag", "where": origin, "event": event]
    }

    static func decode(where origin: Any, event: Any) -> YouTubeMessage? {
        YouTubeMessage.decode(YouTubeMessageTests.data(message(where: origin, event: event)))
    }

    // MARK: accepted

    @Test func everyEventOfTheProtocolTableIsAcceptedFromItsOwnPart() {
        for (origin, event) in Self.allowed {
            #expect(
                Self.decode(where: origin, event: event) == .diag(YouTubeDiag(origin: YouTubeDiag.Origin(rawValue: origin)!, event: event)),
                "\(origin): \(event)"
            )
        }
    }

    @Test func anEventFromAnotherPartIsRefused() {
        for (origin, event) in Self.allowed {
            for other in ["sw", "content", "page"] where other != origin {
                #expect(Self.decode(where: other, event: event) == nil, "\(other): \(event)")
            }
        }
    }

    // MARK: refused

    @Test func theWhereMustBeOneOfThreeParts() {
        for origin: Any in ["", "SW", "background", "sw ", "worker", 1, NSNull(), true] {
            #expect(Self.decode(where: origin, event: "sw-start v=1") == nil, "\(origin)")
        }
        var missing = Self.message(where: "sw", event: "sw-start v=1")
        missing["where"] = nil
        #expect(YouTubeMessage.decode(YouTubeMessageTests.data(missing)) == nil)
    }

    @Test func theEventMustBeAStringOfOneToOneHundredTwentyCharacters() {
        #expect(Self.decode(where: "sw", event: "") == nil)
        #expect(Self.decode(where: "sw", event: 5) == nil)
        #expect(Self.decode(where: "sw", event: NSNull()) == nil)
        var missing = Self.message(where: "sw", event: "")
        missing["event"] = nil
        #expect(YouTubeMessage.decode(YouTubeMessageTests.data(missing)) == nil)
        // The longest an allowed shape can be is a token of 80 characters; one of 120 in all does not exist, so a long one fails on its shape.
        let long = "content-tick-error " + String(repeating: "a", count: 80)
        #expect(long.count <= 120)
        #expect(Self.decode(where: "content", event: long) != nil)
        #expect(Self.decode(where: "content", event: long + String(repeating: "a", count: 40)) == nil)
        #expect(Self.decode(where: "content", event: "content-tick-error " + String(repeating: "a", count: 81)) == nil)
    }

    @Test func anUnknownCodeOrAWrongShapeIsRefused() {
        let bad: [(String, String)] = [
            ("sw", "sw-start"), ("sw", "sw-start v="), ("sw", "sw-start v=1.2.3.4.5"), ("sw", "sw-start v=12345"), ("sw", "sw-start v=1a"),
            ("sw", "sw-start v=0.1.1 extra"), ("sw", "sw-unknown"), ("sw", "sw-msg"), ("sw", "sw-msg captions"), ("sw", "sw-msg captions events="),
            ("sw", "sw-msg captions events=123456"), ("sw", "sw-msg seek"), ("sw", "sw-reject invalid seek"), ("sw", "sw-reject"),
            ("sw", "sw-reconnect after=host-not-found"), ("sw", "sw-reconnect after=Host-Not-Found failures=1"),
            ("sw", "sw-reconnect after= failures=1"), ("sw", "sw-reconnect after=a_b failures=1"), ("sw", "sw-reconnect after=x failures=1234567"),
            ("sw", "sw-inject"), ("sw", "sw-inject tabs=1"), ("sw", "sw-inject tabs=1 injected=1"),
            ("sw", "sw-inject tabs=1 failed=0 injected=1"), ("sw", "sw-inject tabs=1 injected=1 failed=0 extra"),
            ("sw", "sw-inject tabs=-1 injected=0 failed=0"), ("sw", "sw-inject tabs=1000000 injected=0 failed=0"),
            ("sw", "sw-inject tabs=x injected=1 failed=0"), ("sw", "sw-inject tabs=1  injected=1 failed=0"),
            ("sw", "sw-inject tabs=1 injected=1 failed=abcdefghijk"), ("sw", "sw-inject tabs=\u{0661} injected=1 failed=0"),
            ("sw", "sw-access"), ("sw", "sw-access youtube"), ("sw", "sw-access youtube="), ("sw", "sw-access youtube=maybe"),
            ("sw", "sw-access youtube=GRANTED"), ("sw", "sw-access youtube=granted extra"), ("sw", "sw-access  youtube=granted"),
            ("sw", "sw-access site=granted"), ("sw", "sw-access youtube=granted,withheld"),
            ("content", "content-no-lib extra"), ("content", "content-no-lib "), ("content", "content-no-lib=1"),
            ("content", "content-start extra"), ("content", "content-start "), ("content", "content-cc"), ("content", "content-cc maybe"),
            ("content", "content-alive videoid-present=true"), ("content", "content-alive videoid-present=yes playing=true"),
            ("content", "content-send-error count=1"), ("content", "content-send-error x"),
            ("page", "page-wrap fetch=true"), ("page", "page-wrap fetch=1 xhr=0"), ("page", "page-seen beacon"),
            ("page", "page-timedtext html events=1"), ("page", "page-timedtext json3"), ("page", "page-timedtext-status 40"),
            ("page", "page-timedtext-status 4040"), ("page", "page-timedtext-status abc"), ("page", "page-timedtext-status \u{0664}\u{0660}\u{0664}"),
            ("page", "page-timedtext-failed"), ("page", "page-timedtext-parse-error x"),
        ]
        for (origin, event) in bad {
            #expect(Self.decode(where: origin, event: event) == nil, "\(origin): \(event)")
        }
    }

    @Test func spacingAndCaseMustBeExact() {
        for event in [" sw-start v=1", "sw-start  v=1", "sw-start v=1 ", "sw-start\tv=1", "sw-start v=1\n", "SW-START v=1", "sw-start v=UNKNOWN"] {
            #expect(Self.decode(where: "sw", event: event) == nil, "\(event.debugDescription)")
        }
    }

    @Test func nothingThatCouldBeAVideoIdGetsThroughInAnyFreeFormPart() {
        // The only free-form part is a lowercase token; one of exactly eleven characters is refused.
        for token in ["abcdefghijk", "abc-defg-hi", "12345678901", "abcdefghi-x"] {
            #expect(token.count == 11)
            #expect(Self.decode(where: "sw", event: "sw-reconnect after=\(token) failures=1") == nil, "\(token)")
            #expect(Self.decode(where: "content", event: "content-send-error \(token) count=1") == nil, "\(token)")
            #expect(Self.decode(where: "content", event: "content-tick-error \(token)") == nil, "\(token)")
        }
        // Eleven characters inside a longer token are fine, as are tokens of ten and twelve.
        for token in ["abcdefghij", "abcdefghijkl", "abcdefghijk-x"] {
            #expect(Self.decode(where: "content", event: "content-tick-error \(token)") != nil, "\(token)")
        }
    }

    @Test func noUrlGetsThroughAnywhere() {
        for event in [
            "content-tick-error https://example.com/x", "content-tick-error x://y", "page-seen fetch://",
            "sw-reject invalid captions ://", "content-send-error x://x count=1",
        ] {
            #expect(!event.isEmpty)
            #expect(Self.decode(where: String(event.prefix { $0 != "-" }), event: event) == nil, "\(event)")
        }
        #expect(!YouTubeDiag.isAllowed("content-tick-error a://b", from: .content))
    }

    @Test func theEventIsKeptAsItWasSentNothingIsRewritten() {
        let event = "sw-reconnect after=host-has-exited failures=7"
        #expect(Self.decode(where: "sw", event: event) == .diag(YouTubeDiag(origin: .sw, event: event)))
    }

    @Test func theAccessReportIsReadAsGrantedOrWithheldAndNothingElseIs() {
        #expect(YouTubeDiag(origin: .sw, event: "sw-access youtube=granted").siteAccess == .granted)
        #expect(YouTubeDiag(origin: .sw, event: "sw-access youtube=withheld").siteAccess == .withheld)
        for event in ["sw-start v=1", "sw-access youtube=maybe", "sw-access youtube=granted extra", "sw-access", ""] {
            #expect(YouTubeDiag(origin: .sw, event: event).siteAccess == nil, "\(event)")
        }
        // Only the service worker knows what Chrome granted it.
        #expect(YouTubeDiag(origin: .content, event: "sw-access youtube=granted").siteAccess == nil)
        #expect(YouTubeDiag(origin: .page, event: "sw-access youtube=withheld").siteAccess == nil)
    }

    @Test func aDiagIsNotAVideosMessage() {
        let message = Self.decode(where: "sw", event: "sw-start v=1")
        #expect(message?.videoID == nil)
        #expect(message?.typeName == "diag")
    }
}
