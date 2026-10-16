/// What the extension says about itself so that the Mac's log can show what happens inside Chrome, which cannot be
/// looked into from outside: `{"v":1,"type":"diag","where":"sw","event":"sw-start v=0.1.1"}`.
///
/// An event is one fixed code followed by a fixed argument shape: words from a closed list, numbers, booleans, and
/// at most a lowercase `[a-z0-9-]` token for an error. So it cannot carry a title, a URL, a video id or caption
/// text. The extension checks this before it sends; this is the same check again on this side, where an event that
/// fails it is refused like any other bad message and never logged.
public struct YouTubeDiag: Equatable, Sendable {
    /// The part of the extension that sent it: its service worker, a content script or the page script.
    public enum Origin: String, Sendable {
        case sw
        case content
        case page
    }

    /// What Chrome lets the extension do on youtube.com. The user can set the extension's site access to "On click",
    /// which withholds it: Chrome then loads none of the extension's scripts into the page and the extension is silent.
    public enum SiteAccess: Sendable {
        case granted
        case withheld
    }

    /// What the extension says about a command it was given (`YouTubeCommand`).
    public enum CommandAnswer: Equatable, Sendable {
        /// The content script did the command, or could not (no usable button, an advert plays, ...).
        case content(YouTubeCommand, performed: Bool)
        /// The service worker could not hand a command to a tab, or refused it as invalid; it does not say which command.
        case worker
    }

    public static let maxEventLength = 120

    public var origin: Origin
    public var event: String

    public init(origin: Origin, event: String) {
        self.origin = origin
        self.event = event
    }

    /// What the service worker's `sw-access youtube=granted` or `sw-access youtube=withheld` says; nil for any other event,
    /// and for the same words from a part that cannot know.
    public var siteAccess: SiteAccess? {
        guard origin == .sw else { return nil }
        switch event {
        case "sw-access youtube=granted": return .granted
        case "sw-access youtube=withheld": return .withheld
        default: return nil
        }
    }

    /// The command this diagnostic answers, nil for any other event and for the same words from a part that cannot know.
    /// The answer to a command is how the app learns that the host and the extension of this version took it.
    public var commandAnswer: CommandAnswer? {
        let words = event.split(separator: " ", omittingEmptySubsequences: false)
        switch origin {
        case .content:
            // `content-command <action> ok [via=<how>]` or `unavailable [reason=<why>]`: the extension before 0.2.2 says neither.
            guard words.count >= 3, words.count <= 4, words[0] == "content-command", let command = YouTubeCommand(rawValue: String(words[1])),
                  Self.isOutcome(words[2...])
            else { return nil }
            return .content(command, performed: words[2] == "ok")
        case .sw:
            return event == "sw-command-no-tab" || event == "sw-reject invalid command" ? .worker : nil
        case .page:
            return nil
        }
    }

    /// Whether `event` is one of the extension's, sent by `origin`: its code starts with the part's name, its
    /// arguments have the shape that code has, and no run of video-id characters is exactly eleven long.
    public static func isAllowed(_ event: String, from origin: Origin) -> Bool {
        guard !event.isEmpty, event.utf16.count <= maxEventLength, !event.contains("://") else { return false }
        let code = event.prefix { $0 != " " }
        let arguments = event.dropFirst(code.count)
        guard code.hasPrefix(origin.rawValue + "-"), areValid(arguments, for: String(code)) else { return false }
        // Would look like a video id. The arguments of a code whose arguments are a closed list of words are not looked at:
        // one of the words, `unavailable`, is eleven letters long, and nothing else can stand where the list does.
        let scanned = closedWordCodes.contains(String(code)) ? Substring(code) : Substring(event)
        return !scanned.split(whereSeparator: { !isIDCharacter($0) }).contains { $0.count == 11 }
    }

    /// Codes whose arguments are a closed list of words and nothing else (see `isAllowed`).
    private static let closedWordCodes: Set<String> = ["content-command", "content-tabcommand"]

    // MARK: shapes

    /// How a command went: `ok` and how it was done, or `unavailable` and why (the word after it may be left out). Closed lists of words.
    private static let doneVia: Set<Substring> = ["button", "href", "upnext", "endscreen", "restart", "history"]
    private static let unavailableReasons: Set<Substring> = ["ad", "none", "refused", "error"]

    private static func isOutcome(_ words: ArraySlice<Substring>) -> Bool {
        guard let first = words.first, words.count <= 2 else { return false }
        let detail = words.count == 2 ? value(of: first == "ok" ? "via" : "reason", in: words[words.startIndex + 1]) : nil
        switch first {
        case "ok": return words.count == 1 || detail.map(doneVia.contains) == true
        case "unavailable": return words.count == 1 || detail.map(unavailableReasons.contains) == true
        default: return false
        }
    }

    /// `arguments` is what follows the code: nothing, or a space and then the words separated by single spaces.
    private static func areValid(_ arguments: Substring, for code: String) -> Bool {
        var words: [Substring] = []
        if !arguments.isEmpty {
            guard arguments.first == " " else { return false }
            words = arguments.dropFirst().split(separator: " ", omittingEmptySubsequences: false)
        }
        switch code {
        case "content-start", "content-no-lib", "content-video-found", "content-video-missing", "page-timedtext-parse-error", "page-timedtext-too-large":
            return words.isEmpty
        case "sw-start":
            return words.count == 1 && value(of: "v", in: words[0]).map { $0 == "unknown" || isVersion($0) } == true
        case "sw-msg":
            if words.count == 1 { return ["playback", "clear", "tab"].contains(words[0]) }
            return words.count == 2 && words[0] == "captions" && value(of: "events", in: words[1]).map { isNumber($0, digits: 1...5) } == true
        case "sw-reject":
            if words.count == 1 { return words[0] == "untrusted" }
            return words.count == 2 && words[0] == "invalid" && ["captions", "playback", "clear", "diag", "command", "tab", "tabcommand", "unknown"].contains(words[1])
        case "sw-reconnect":
            return words.count == 2 && value(of: "after", in: words[0]).map(isToken) == true
                && value(of: "failures", in: words[1]).map { isNumber($0, digits: 1...6) } == true
        case "sw-inject":
            return words.count == 3 && value(of: "tabs", in: words[0]).map { isNumber($0, digits: 1...6) } == true
                && value(of: "injected", in: words[1]).map { isNumber($0, digits: 1...6) } == true
                && value(of: "failed", in: words[2]).map { isNumber($0, digits: 1...6) } == true
        case "sw-access":
            return words.count == 1 && value(of: "youtube", in: words[0]).map { $0 == "granted" || $0 == "withheld" } == true
        case "sw-command-no-tab", "sw-tabcommand-no-tab":
            return words.isEmpty
        case "content-tabcommand":
            return words.count == 2 && ["play", "pause", "toggle", "next", "previous", "seek"].contains(words[0])
                && (words[1] == "ok" || words[1] == "unavailable")
        case "content-command":
            return (2...3).contains(words.count) && (words[0] == "next" || words[0] == "previous") && isOutcome(words[1...])
        case "content-cc":
            return words.count == 1 && (words[0] == "on" || words[0] == "off")
        case "content-send-error":
            return words.count == 2 && isToken(words[0]) && value(of: "count", in: words[1]).map { isNumber($0, digits: 1...6) } == true
        case "content-alive":
            return words.count == 2 && value(of: "videoid-present", in: words[0]).map(isBoolean) == true
                && value(of: "playing", in: words[1]).map(isBoolean) == true
        case "content-tick-error":
            return words.count == 1 && isToken(words[0])
        case "page-wrap", "page-wrap-check":
            return words.count == 2 && value(of: "fetch", in: words[0]).map(isBoolean) == true
                && value(of: "xhr", in: words[1]).map(isBoolean) == true
        case "page-seen", "page-timedtext-failed":
            return words.count == 1 && (words[0] == "fetch" || words[0] == "xhr")
        case "page-timedtext":
            return words.count == 2 && ["json3", "srv3", "other"].contains(words[0])
                && value(of: "events", in: words[1]).map { isNumber($0, digits: 1...5) } == true
        case "page-timedtext-status":
            return words.count == 1 && isNumber(words[0], digits: 3...3)
        default:
            return false
        }
    }

    /// What follows `key=`, nil when the word is not that.
    private static func value(of key: String, in word: Substring) -> Substring? {
        word.hasPrefix(key + "=") ? word.dropFirst(key.count + 1) : nil
    }

    private static func isBoolean(_ word: Substring) -> Bool { word == "true" || word == "false" }

    /// One to four numbers of one to four digits, separated by dots.
    private static func isVersion(_ word: Substring) -> Bool {
        let parts = word.split(separator: ".", omittingEmptySubsequences: false)
        return (1...4).contains(parts.count) && parts.allSatisfy { isNumber($0, digits: 1...4) }
    }

    private static func isNumber(_ word: Substring, digits: ClosedRange<Int>) -> Bool {
        digits.contains(word.utf8.count) && word.utf8.allSatisfy { (48...57).contains($0) }
    }

    /// The lowercase token the extension makes of an error: one to eighty of `a-z`, `0-9` and `-`.
    private static func isToken(_ word: Substring) -> Bool {
        (1...80).contains(word.utf8.count) && word.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
    }

    private static func isIDCharacter(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isLetter || character.isNumber || character == "_" || character == "-"
    }
}
