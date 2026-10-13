import Foundation

nonisolated enum MeetingProvider: Equatable, Sendable {
    case zoom, googleMeet, teams, webex, faceTime
}

nonisolated struct MeetingLink: Equatable, Sendable {
    var provider: MeetingProvider
    var url: URL
}

/// Finds the join link of an online meeting. EventKit has no property for it, so it is read out of the text the
/// organizer's invite leaves in the event.
nonisolated enum MeetingLinkDetector {
    /// A link ends at whitespace or at a character that marks the end of an HTML attribute or tag.
    private static let rest = #"[^\s"<>]"#

    /// Hosts match in any case, since people type and paste them that way. ZoomGov also lives on `zoomgov.com`, and
    /// Zoom and Webex hosts can have several labels in front (`acme.my.webex.com`). A Zoom passcode can carry `%` and `+`.
    private static let patterns: [(provider: MeetingProvider, regex: NSRegularExpression)] = {
        let table: [(MeetingProvider, String)] = [
            (.zoom, #"https://([\w-]+\.)*zoom(\.us|gov\.(us|com))/(j|my|w)/[\w?=&.%+\-]+"#),
            (.googleMeet, #"https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}"#),
            (.teams, #"https://teams\.(microsoft|live)\.com/(l/meetup-join|meet)/\#(rest)+"#),
            (.webex, #"https://([\w-]+\.)+webex\.com/\#(rest)+"#),
            (.faceTime, #"https://facetime\.apple\.com/join\#(rest)+"#),
        ]
        return table.map { (provider: $0.0, regex: try! NSRegularExpression(pattern: $0.1, options: .caseInsensitive)) }
    }()

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
        return patterns
            .compactMap { pattern -> (location: Int, link: MeetingLink)? in
                guard let match = pattern.regex.firstMatch(in: text, range: whole), let range = Range(match.range, in: text),
                      let url = URL(string: trimmed(String(text[range]))) else { return nil }
                return (match.range.location, MeetingLink(provider: pattern.provider, url: url))
            }
            .min { $0.location < $1.location }?
            .link
    }

    private static func trimmed(_ link: String) -> String {
        var link = Substring(link)
        while let last = link.unicodeScalars.last, trailingPunctuation.contains(last) {
            link = link.dropLast()
        }
        return String(link)
    }
}
