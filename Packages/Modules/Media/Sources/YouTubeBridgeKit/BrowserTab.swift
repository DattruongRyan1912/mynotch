import Foundation

/// What a page in Chrome says about the media it plays or has paused (`tab`): one report per page, sent when the media does
/// something and again every few seconds. The extension makes it from what the page itself shows (its Media Session, else
/// its title) and sends no address, only the site's host name; no cover and no icon.
public struct BrowserTab: Equatable, Sendable {
    /// Chrome's id of the tab. Only meaningful for the Chrome (the connection) that sent it: two profiles may use the same numbers.
    public var tab: Int
    /// The page's host name, or empty when it has none that is plain (an IP v6 address).
    public var site: String
    public var title: String
    public var artist: String?
    public var album: String?
    public var isPlaying: Bool
    /// Seconds into the media when the report was made.
    public var time: Double
    /// nil for a live stream, or while it is not known.
    public var duration: Double?
    public var rate: Double
    public var isLive: Bool
    /// An element of the page is the media. A page with none only says through its Media Session what it plays, which any page can say.
    public var hasElement: Bool
    /// Chrome says the tab is making sound (the extension asks it; the page cannot say so).
    public var isAudible: Bool
    /// The other names the page gives what it plays (its og:title, keywords and first headings, joined by " | "): a film's original
    /// title on a site that shows it under a translated one. nil from an extension that predates them, or when the page gives none.
    public var names: String?

    /// A page whose media is not heard and not an element has nothing but its own word for it, and does not lead (see `MediaSourceBook`).
    public var isBelieved: Bool { hasElement || isAudible }

    public init(
        tab: Int, site: String, title: String, artist: String? = nil, album: String? = nil, isPlaying: Bool,
        time: Double, duration: Double? = nil, rate: Double = 1, isLive: Bool = false, hasElement: Bool = true, isAudible: Bool = false,
        names: String? = nil
    ) {
        self.tab = tab
        self.site = site
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.time = time
        self.duration = duration
        self.rate = rate
        self.isLive = isLive
        self.hasElement = hasElement
        self.isAudible = isAudible
        self.names = names
    }

    /// Chrome's tab ids are small integers; this is the range the extension and the app both accept.
    public static let maxTabID = Int(Int32.max)
    /// No media is longer than this many seconds (about 115 days); the same limit as the extension's.
    public static let maxSeconds = 10_000_000.0
    public static let maxNameLength = 200
    public static let maxNamesLength = 300
}

/// What the top frame of a tab that makes sound calls what it shows (`pagenames`), when the media plays in a frame the extension does
/// not read: a film site's player, whose page names the film by its translated title and, in its og:title or headings, by its own.
public struct BrowserPageNames: Equatable, Sendable {
    public var tab: Int
    /// The document's title.
    public var title: String
    /// As `BrowserTab.names`.
    public var names: String

    public init(tab: Int, title: String, names: String) {
        self.tab = tab
        self.title = title
        self.names = names
    }
}
