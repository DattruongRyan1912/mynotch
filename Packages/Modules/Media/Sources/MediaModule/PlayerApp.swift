import AppKit
import UniformTypeIdentifiers

/// The app behind a bundle ID, as the user knows it from the Dock.
struct PlayerApp {
    var name: String
    var icon: NSImage

    /// A running app first (its localized name), then an installed one; nil when the app is not on this Mac.
    static func installed(bundleIdentifier: String) -> PlayerApp? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
           let name = running.localizedName {
            return PlayerApp(name: name, icon: running.icon ?? NSWorkspace.shared.icon(for: .application))
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
        return PlayerApp(
            name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name,
            icon: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        )
    }

    enum BrowserKind: Sendable {
        case chromium(bundleID: String)
        case safari(bundleID: String)
    }

    static func browserKind(for bundleID: String) -> BrowserKind? {
        switch bundleID {
        case "com.google.Chrome", "com.google.Chrome.canary", "com.brave.Browser",
             "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi":
            return .chromium(bundleID: bundleID)
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            return .safari(bundleID: bundleID)
        default:
            return nil
        }
    }

    /// Brings the application with `bundleIdentifier` to the front, unhiding and reopening its window if needed.
    /// If the app is a browser, also attempts to switch directly to the tab playing the media (YouTube, SoundCloud and other `mediaSites`):
    /// a media tab with the track's title, then any tab with it, then the first media tab.
    @discardableResult
    @MainActor
    static func activate(bundleIdentifier: String, title: String? = nil) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return false
        }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            if running.isHidden {
                running.unhide()
            }
            running.activate(options: [.activateAllWindows])
            if let kind = browserKind(for: bundleIdentifier) {
                focusBrowserTab(kind: kind, title: title)
                return true
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
        return true
    }

    nonisolated static func escapeForAppleScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// Sites whose tab is the player: without a tab whose title matches, the first tab on one of them is the one to show.
    nonisolated static let mediaSites = [
        "youtube.com", "youtu.be", "soundcloud.com", "open.spotify.com", "music.apple.com",
        "zingmp3.vn", "nhaccuatui.com", "bandcamp.com", "mixcloud.com", "deezer.com", "tidal.com",
    ]

    nonisolated static func buildBrowserScript(kind: BrowserKind, title: String?) -> String {
        let cleanTitle = title.map(escapeForAppleScript) ?? ""
        let mediaCondition = mediaSites.map { "tURL contains \"\($0)\"" }.joined(separator: " or ")
        switch kind {
        case .chromium(let bundleID):
            return """
            tell application id "\(bundleID)"
                set matchTab to 0
                set matchWin to missing value
                set matchTitleTab to 0
                set matchTitleWin to missing value
                repeat with w in windows
                    set tabIndex to 1
                    repeat with t in tabs of w
                        try
                            set tURL to URL of t
                            set tTitle to title of t
                            set isMedia to (\(mediaCondition))
                            if isMedia and "\(cleanTitle)" is not "" and (tTitle contains "\(cleanTitle)" or "\(cleanTitle)" contains tTitle) then
                                set active tab index of w to tabIndex
                                set index of w to 1
                                activate
                                return "found"
                            end if
                            if isMedia and matchTab is 0 then
                                set matchTab to tabIndex
                                set matchWin to w
                            end if
                            if "\(cleanTitle)" is not "" and (tTitle contains "\(cleanTitle)" or "\(cleanTitle)" contains tTitle) then
                                if matchTitleTab is 0 then
                                    set matchTitleTab to tabIndex
                                    set matchTitleWin to w
                                end if
                            end if
                        end try
                        set tabIndex to tabIndex + 1
                    end repeat
                end repeat
                if matchTitleTab > 0 then
                    set active tab index of matchTitleWin to matchTitleTab
                    set index of matchTitleWin to 1
                    activate
                    return "found"
                end if
                if matchTab > 0 then
                    set active tab index of matchWin to matchTab
                    set index of matchWin to 1
                    activate
                    return "found"
                end if
                activate
                return "activated"
            end tell
            """
        case .safari(let bundleID):
            return """
            tell application id "\(bundleID)"
                set matchTab to missing value
                set matchWin to missing value
                set matchTitleTab to missing value
                set matchTitleWin to missing value
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            set tURL to URL of t
                            set tTitle to name of t
                            set isMedia to (\(mediaCondition))
                            if isMedia and "\(cleanTitle)" is not "" and (tTitle contains "\(cleanTitle)" or "\(cleanTitle)" contains tTitle) then
                                set current tab of w to t
                                set index of w to 1
                                activate
                                return "found"
                            end if
                            if isMedia and matchTab is missing value then
                                set matchTab to t
                                set matchWin to w
                            end if
                            if "\(cleanTitle)" is not "" and (tTitle contains "\(cleanTitle)" or "\(cleanTitle)" contains tTitle) then
                                if matchTitleTab is missing value then
                                    set matchTitleTab to t
                                    set matchTitleWin to w
                                end if
                            end if
                        end try
                    end repeat
                end repeat
                if matchTitleTab is not missing value then
                    set current tab of matchTitleWin to matchTitleTab
                    set index of matchTitleWin to 1
                    activate
                    return "found"
                end if
                if matchTab is not missing value then
                    set current tab of matchWin to matchTab
                    set index of matchWin to 1
                    activate
                    return "found"
                end if
                activate
                return "activated"
            end tell
            """
        }
    }

    nonisolated private static func focusBrowserTab(kind: BrowserKind, title: String?) {
        Task.detached(priority: .userInitiated) {
            let scriptSource = buildBrowserScript(kind: kind, title: title)
            guard let script = NSAppleScript(source: scriptSource) else { return }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
        }
    }
}

/// Remembers each bundle ID's app, including "not installed", for as long as a view keeps it: LaunchServices
/// lookups are too slow to repeat on every redraw of a list.
final class PlayerAppCache {
    private let lookUp: @MainActor (String) -> PlayerApp?
    private var apps: [String: PlayerApp?] = [:]

    init(lookUp: @escaping @MainActor (String) -> PlayerApp? = PlayerApp.installed) {
        self.lookUp = lookUp
    }

    func app(for bundleID: String) -> PlayerApp? {
        if let cached = apps[bundleID] { return cached }
        let app = lookUp(bundleID)
        apps[bundleID] = .some(app)
        return app
    }
}
