import Foundation

nonisolated enum MeetingProvider: Equatable, Sendable {
    case zoom, googleMeet, teams, webex, faceTime, whereby, jitsi
}

nonisolated struct MeetingLink: Equatable, Sendable {
    var provider: MeetingProvider
    var url: URL
}

/// Finds the join link of an online meeting. EventKit has no property for it, so it is read out of the text the
/// organizer's invite leaves in the event. Jitsi on a server of one's own has no address of its own to recognise (any
/// `https://<host>/<room>` could be a document), so it counts only when the invite says "jitsi" itself.
nonisolated enum MeetingLinkDetector {
    /// A link ends at whitespace or at a character that marks the end of an HTML attribute or tag.
    private static let rest = #"[^\s"<>]"#

    /// A room: one path segment, and the address ends there or goes on into a query or a fragment. A longer path,
    /// a file (`robots.txt`) or a bare host is a page of the website. A `/` at the very end is let go, as is a
    /// sentence's full stop, and neither is part of the address.
    private static let room = #"[\w%-]+(?![\w%-]|\.\w|/[^\s"<>])(?:[?#]\#(rest)*)?"#

    /// Hosts match in any case, since people type and paste them that way. ZoomGov also lives on `zoomgov.com`, and
    /// Zoom, Webex and Whereby hosts can have several labels in front (`acme.my.webex.com`, `acme.whereby.com`). A Zoom
    /// passcode can carry `%` and `+`. Whereby and Jitsi take rooms only (see `room`); the help, support and docs
    /// sites of Whereby have one segment pages too and are left out by name.
    private static let patterns: [(provider: MeetingProvider, regex: NSRegularExpression)] = {
        let table: [(MeetingProvider, String)] = [
            (.zoom, #"https://([\w-]+\.)*zoom(\.us|gov\.(us|com))/(j|my|w)/[\w?=&.%+\-]+"#),
            (.googleMeet, #"https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}"#),
            (.teams, #"https://teams\.(microsoft|live)\.com/(l/meetup-join|meet)/\#(rest)+"#),
            (.webex, #"https://([\w-]+\.)+webex\.com/\#(rest)+"#),
            (.faceTime, #"https://facetime\.apple\.com/join\#(rest)+"#),
            (.whereby, #"https://(?!(?:www|support|docs|help|developers?|blog|status)\.)([\w-]+\.)*whereby\.com/\#(room)"#),
            (.jitsi, #"https://([\w-]+\.)*meet\.jit\.si/\#(room)"#),
        ]
        return table.map { (provider: $0.0, regex: try! NSRegularExpression(pattern: $0.1, options: .caseInsensitive)) }
    }()

    /// Every `https://` address in a text, to be looked at one by one for a Jitsi room.
    private static let anyLink = try! NSRegularExpression(pattern: #"https://\#(rest)+"#, options: .caseInsensitive)

    /// What a room on a server of one's own looks like: one path segment that is a name (three characters or more, no
    /// dot, so not a file), then at most a query or a fragment. The first group is the host.
    private static let ownServerRoom = try! NSRegularExpression(
        pattern: #"^https://((?:[\w-]+\.)+[\w-]+)(?::\d+)?/[\w%-]{3,}(?:[?#].*)?$"#, options: .caseInsensitive
    )

    /// Punctuation that follows a link in prose or sits around it as a wrapper, not part of the address.
    private static let trailingPunctuation = CharacterSet(charactersIn: ")>],.;")

    /// Looks in `url`, then `location`, then `notes`, and returns the first link of the first field that has one.
    /// Within a field the link that comes first in the text wins, whatever its provider.
    static func detect(url: URL?, location: String?, notes: String?) -> MeetingLink? {
        for text in [url?.absoluteString, location, notes] {
            if let text, let link = firstLink(in: text) { return link }
        }
        return nil
    }

    private static func firstLink(in text: String) -> MeetingLink? {
        let whole = NSRange(text.startIndex..., in: text)
        var found = patterns.compactMap { pattern -> (location: Int, link: MeetingLink)? in
            guard let match = pattern.regex.firstMatch(in: text, range: whole), let range = Range(match.range, in: text),
                  let url = URL(string: trimmed(String(text[range]))) else { return nil }
            return (match.range.location, MeetingLink(provider: pattern.provider, url: url))
        }
        if let room = ownServerJitsiRoom(in: text, whole: whole) { found.append(room) }
        return found.min { $0.location < $1.location }?.link
    }

    /// The first address that is a Jitsi room on a server of one's own: its host says "jitsi", or the line it is on or
    /// the line above says it before the address. The text since the previous address is all that counts, so the
    /// word is never shared by two addresses.
    private static func ownServerJitsiRoom(in text: String, whole: NSRange) -> (location: Int, link: MeetingLink)? {
        var contextStart = text.startIndex
        for match in anyLink.matches(in: text, range: whole) {
            guard let range = Range(match.range, in: text) else { continue }
            let context = text[contextStart..<range.lowerBound]
            contextStart = range.upperBound
            let address = trimmed(String(text[range]))
            let addressRange = NSRange(address.startIndex..., in: address)
            guard let room = ownServerRoom.firstMatch(in: address, range: addressRange), let hostRange = Range(room.range(at: 1), in: address),
                  !isNotARoomHost(String(address[hostRange])), let url = URL(string: address) else { continue }
            // `isNewline` also takes CRLF (one `Character`), CR and the Unicode separators, which a "\n" would not.
            let nearby = context.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).suffix(2)
            if mentionsJitsi(address[hostRange]) || nearby.contains(where: mentionsJitsi) {
                return (match.range.location, MeetingLink(provider: .jitsi, url: url))
            }
        }
        return nil
    }

    /// Whatever the Mac's language, so a Turkish locale does not part "JITSI" from "jitsi".
    private static func mentionsJitsi(_ text: some StringProtocol) -> Bool {
        text.range(of: "jitsi", options: .caseInsensitive) != nil
    }

    /// The project's website and forum say "jitsi" too, and so do the pages made with GitHub or GitLab (its handbook is
    /// `jitsi.github.io`); none of them serves rooms.
    private static func isNotARoomHost(_ host: String) -> Bool {
        let host = host.lowercased()
        return host == "jitsi.org" || [".jitsi.org", ".github.io", ".gitlab.io"].contains { host.hasSuffix($0) }
    }

    private static func trimmed(_ link: String) -> String {
        var link = Substring(link)
        while let last = link.unicodeScalars.last, trailingPunctuation.contains(last) {
            link = link.dropLast()
        }
        return String(link)
    }
}
