import Foundation
import Testing
@testable import YouTubeBridgeKit

@Suite struct BrowserTabMessageTests {
    static func tab(
        tab: Any = 7, site: Any = "music.example.com", title: Any = "Song", artist: Any? = "Artist", album: Any? = "", state: Any = "playing",
        time: Any = 12.5, duration: Any? = 200.0, rate: Any = 1.0, live: Any = false
    ) -> [String: Any] {
        var object: [String: Any] = [
            "v": 1, "type": "tab", "tab": tab, "site": site, "title": title, "state": state, "time": time, "rate": rate, "live": live,
        ]
        object["artist"] = artist
        object["album"] = album
        object["duration"] = duration ?? NSNull()
        return object
    }

    static func decode(_ object: Any) -> YouTubeMessage? {
        YouTubeMessageTests.decode(object)
    }

    @Test func aTabMessageDecodesToItsFields() {
        #expect(Self.decode(Self.tab()) == .tab(BrowserTab(
            tab: 7, site: "music.example.com", title: "Song", artist: "Artist", album: nil, isPlaying: true,
            time: 12.5, duration: 200, rate: 1, isLive: false
        )))
    }

    @Test func pausedAndLiveAndWithoutAnArtistOrALength() {
        let message = Self.decode(Self.tab(artist: "", album: "Album", state: "paused", duration: nil, live: true))
        #expect(message == .tab(BrowserTab(
            tab: 7, site: "music.example.com", title: "Song", artist: nil, album: "Album", isPlaying: false,
            time: 12.5, duration: nil, rate: 1, isLive: true
        )))
        // Fields the extension always sends may be absent in a report of a page that knows nothing of them.
        var bare = Self.tab()
        bare["artist"] = nil
        bare["album"] = nil
        guard case .tab(let tab) = Self.decode(bare) else { Issue.record("not decoded"); return }
        #expect(tab.artist == nil && tab.album == nil)
    }

    @Test func whatChromeHearsAndWhatIsAnElementAreCarriedAndDefaultToAnElementThatIsNotHeard() {
        var report = Self.tab()
        report["element"] = false
        report["audible"] = true
        guard case .tab(let heard) = Self.decode(report) else { Issue.record("not decoded"); return }
        #expect(!heard.hasElement && heard.isAudible && heard.isBelieved, "no element, but Chrome hears it")
        report["audible"] = false
        guard case .tab(let silent) = Self.decode(report) else { Issue.record("not decoded"); return }
        #expect(!silent.hasElement && !silent.isAudible && !silent.isBelieved, "a page's word alone is not believed")
        // An extension that predates both fields reports elements.
        guard case .tab(let older) = Self.decode(Self.tab()) else { Issue.record("not decoded"); return }
        #expect(older.hasElement && !older.isAudible && older.isBelieved)
    }

    @Test func anElementOrAudibleThatIsNotABooleanIsRefused() {
        for key in ["element", "audible"] {
            for value: Any in ["true", 1, [true]] {
                var object = Self.tab()
                object[key] = value
                #expect(YouTubeMessage.check(YouTubeMessageTests.data(object)) == .failure(.invalidTab), Comment(rawValue: "\(key) \(value)"))
            }
        }
    }

    @Test func aPageWithoutAPlainHostNameHasNoSite() {
        if case .tab(let tab) = Self.decode(Self.tab(site: "")) { #expect(tab.site.isEmpty) } else { Issue.record("not decoded") }
    }

    @Test func textIsCleanedAndCut() {
        let message = Self.decode(Self.tab(title: "  A\n\n  B\t C ", artist: String(repeating: "x", count: 500)))
        guard case .tab(let tab) = message else { Issue.record("not decoded"); return }
        #expect(tab.title == "A B C")
        #expect(tab.artist?.count == BrowserTab.maxNameLength)
        if case .tab(let long) = Self.decode(Self.tab(title: String(repeating: "t", count: 400))) {
            #expect(long.title.count == YouTubeMessage.maxTitleLength)
        } else {
            Issue.record("not decoded")
        }
    }

    @Test func aTabMessageIsFromThePageAndAboutNoVideo() {
        let message = Self.decode(Self.tab())
        #expect(message?.isFromPage == true)
        #expect(message?.videoID == nil)
        #expect(message?.typeName == "tab")
        let gone = Self.decode(["v": 1, "type": "tabgone", "tab": 7])
        #expect(gone == .tabGone(tab: 7))
        #expect(gone?.isFromPage == true)
        #expect(gone?.videoID == nil)
        #expect(gone?.typeName == "tabgone")
    }

    @Test func aTabMessageIsRefusedWhenAnyFieldIsOutOfRange() {
        let bad: [[String: Any]] = [
            Self.tab(tab: -1), Self.tab(tab: 2_147_483_648), Self.tab(tab: 1.5), Self.tab(tab: "7"), Self.tab(tab: NSNull()),
            Self.tab(site: "Example.com"), Self.tab(site: "a b"), Self.tab(site: "a/b"), Self.tab(site: "https://a.com"), Self.tab(site: "a:80"),
            Self.tab(site: "-a.com"), Self.tab(site: "a.com-"), Self.tab(site: String(repeating: "a", count: 101)), Self.tab(site: 5),
            Self.tab(title: ""), Self.tab(title: "   "), Self.tab(title: 5), Self.tab(title: NSNull()),
            Self.tab(state: "stopped"), Self.tab(state: "PLAYING"), Self.tab(state: true),
            Self.tab(time: -1), Self.tab(time: 1e8), Self.tab(time: "1"), Self.tab(time: NSNull()),
            Self.tab(duration: -1.0), Self.tab(duration: 1e8), Self.tab(duration: "3"),
            Self.tab(rate: 0), Self.tab(rate: -1), Self.tab(rate: 17), Self.tab(rate: "1"),
            Self.tab(live: "false"), Self.tab(live: NSNull()),
            ["v": 2, "type": "tab", "tab": 7],
            ["v": 1, "type": "tab"],
        ]
        for object in bad {
            let result = YouTubeMessage.check(YouTubeMessageTests.data(object))
            #expect(result == .failure(.invalidTab) || result == .failure(.unsupportedVersion), Comment(rawValue: "\(object)"))
        }
    }

    @Test func aMissingFieldIsRefusedAsAnInvalidTab() {
        for key in ["tab", "site", "title", "state", "time", "rate", "live"] {
            var object = Self.tab()
            object[key] = nil
            #expect(YouTubeMessage.check(YouTubeMessageTests.data(object)) == .failure(.invalidTab), Comment(rawValue: key))
        }
    }

    @Test func textFromAPageCannotHoldAControlCharacterOrTurnTheLineAround() {
        let message = Self.decode(Self.tab(title: "Song\u{202E}gnos\u{0007}\u{200F} two", artist: "A\u{2066}B\u{009B}C"))
        guard case .tab(let tab) = message else { Issue.record("not decoded"); return }
        #expect(tab.title == "Songgnos two")
        #expect(tab.artist == "ABC")
        // A title of nothing but such marks is no title.
        #expect(YouTubeMessage.check(YouTubeMessageTests.data(Self.tab(title: "\u{202E}\u{200F} \u{0007}"))) == .failure(.invalidTab))
    }

    @Test func aTabGoneMessageNeedsATabInRange() {
        for tab: Any in [-1, 2_147_483_648, 1.5, "7", NSNull()] {
            #expect(YouTubeMessage.check(YouTubeMessageTests.data(["v": 1, "type": "tabgone", "tab": tab])) == .failure(.invalidTab), Comment(rawValue: "\(tab)"))
        }
        #expect(YouTubeMessage.check(YouTubeMessageTests.data(["v": 1, "type": "tabgone"])) == .failure(.invalidTab))
        #expect(Self.decode(["v": 1, "type": "tabgone", "tab": 0]) == .tabGone(tab: 0))
    }

    @Test func theReasonForRefusalIsAFixedWord() {
        #expect(YouTubeMessage.Rejection.invalidTab.rawValue == "invalid-tab")
    }
}
