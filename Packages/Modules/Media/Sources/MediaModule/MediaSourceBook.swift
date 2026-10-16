import Foundation

/// Every source of sound that is live, merged, and which of them the notch follows. Pure: what the system, the apps and the
/// browser tabs report goes in, with the time of each report; the chips, the primary source and the one the player shows come out.
///
/// - **Merging.** The system's now-playing session is one source's: an app's (by bundle id, since an app has one session at a time
///   and its title lags at a track change), or the tab's of a browser that has one with the same title once normalised. A session of
///   an app the book has no other word on is a source of its own (VLC, a browser the extension does not know). Such a source takes
///   the system's state, which is richer than what an app or a tab reports of itself.
/// - **Primary** (what the closed notch, the lock screen and the hotkeys follow): the user's pin while that source is there;
///   otherwise the source that started playing most recently. Pausing a source never takes the place from it unless another
///   source plays, and a source that goes away hands it on to the one playing, or else the one that was playing last.
/// - **Shown** in the player: the source the user chose with a chip while it is there, else the primary.
nonisolated struct MediaSourceBook: Sendable {
    /// A tab that has not been heard from for this long is not there any more. A page that plays reports every 5 s and a paused one
    /// every 30 s, but Chrome may let a tab it put to sleep stay quiet for a minute or two.
    static let tabLiveWindow: TimeInterval = 150

    private(set) var entries: [MediaSourceEntry] = []
    private(set) var primaryID: MediaSourceID?
    private(set) var pinnedID: MediaSourceID?
    private(set) var selectedID: MediaSourceID?

    private struct TabSession: Sendable {
        var state: NowPlayingState
        var site: String
        var heardAt: Date
    }

    private var system: NowPlayingState?
    private var apps: [String: NowPlayingState] = [:]
    private var tabs: [TabRef: TabSession] = [:]
    /// Apps that must not be shown from what they report of themselves: the user did not let MyNotch control them.
    private var hiddenApps: Set<String> = []
    /// When each source began its present stretch of playing, when it last played, and when it was first seen.
    private var playingSince: [MediaSourceID: Date] = [:]
    private var lastPlayed: [MediaSourceID: Date] = [:]
    private var firstSeen: [MediaSourceID: Date] = [:]

    var primary: MediaSourceEntry? { primaryID.flatMap(entry(_:)) }

    /// What the player shows: the chosen source, else the primary.
    var displayedID: MediaSourceID? { selectedID ?? primaryID }
    var displayed: MediaSourceEntry? { displayedID.flatMap(entry(_:)) }

    func entry(_ id: MediaSourceID) -> MediaSourceEntry? { entries.first { $0.id == id } }

    /// The tab source with this reference, whether or not the system plays it.
    func entry(forTab ref: TabRef) -> MediaSourceEntry? { entry(.tab(ref)) }

    /// When the next tab will go stale, so that one timer is enough; nil while there is none.
    var nextExpiry: Date? { tabs.values.map { $0.heardAt + Self.tabLiveWindow }.min() }

    // MARK: what the sources report

    /// The system's now-playing session; nil, or one without a title, when nothing plays.
    mutating func setSystem(_ state: NowPlayingState?, at now: Date) {
        system = state?.isActive == true ? state : nil
        refresh(at: now)
    }

    /// What an app says of itself (Apple Events, a player's own notification); nil when it has quit or has nothing loaded.
    mutating func setApp(_ bundleID: String, state: NowPlayingState?, at now: Date) {
        apps[bundleID] = state
        refresh(at: now)
    }

    /// What a page says of its media; nil when it has none any more.
    mutating func setTab(_ ref: TabRef, state: NowPlayingState?, site: String = "", at now: Date) {
        tabs[ref] = state.map { TabSession(state: $0, site: site, heardAt: now) }
        refresh(at: now)
    }

    /// The Chrome behind `connection` has gone: so have its tabs.
    mutating func removeTabs(ofConnection connection: Int, at now: Date) {
        tabs = tabs.filter { $0.key.connection != connection }
        refresh(at: now)
    }

    /// Every tab is gone: the extension's bridge is off.
    mutating func removeAllTabs(at now: Date) {
        guard !tabs.isEmpty else { return }
        tabs = [:]
        refresh(at: now)
    }

    /// Drops the tabs that have not been heard from for `tabLiveWindow`.
    mutating func expireTabs(at now: Date) {
        tabs = tabs.filter { now.timeIntervalSince($0.value.heardAt) < Self.tabLiveWindow }
        refresh(at: now)
    }

    /// Apps the user did not allow MyNotch to control are not shown from what they report of themselves, but the system's own session
    /// for them is: it is controlled through the system.
    mutating func setHidden(_ bundleID: String, _ isHidden: Bool, at now: Date) {
        guard hiddenApps.contains(bundleID) != isHidden else { return }
        if isHidden { hiddenApps.insert(bundleID) } else { hiddenApps.remove(bundleID) }
        refresh(at: now)
    }

    func isHidden(_ bundleID: String) -> Bool { hiddenApps.contains(bundleID) }

    // MARK: what the user chooses

    /// Always show this source in the notch, while it is there. Pinning another source moves the pin; a source that is not live is
    /// no one to pin.
    mutating func pin(_ id: MediaSourceID, at now: Date) {
        guard entry(id) != nil else { return }
        pinnedID = id
        refresh(at: now)
    }

    mutating func unpin(at now: Date) {
        guard pinnedID != nil else { return }
        pinnedID = nil
        refresh(at: now)
    }

    mutating func togglePin(_ id: MediaSourceID, at now: Date) {
        if pinnedID == id { unpin(at: now) } else { pin(id, at: now) }
    }

    /// Show this source in the player. Choosing the primary is going back to following it.
    mutating func select(_ id: MediaSourceID, at now: Date) {
        guard entry(id) != nil else { return }
        selectedID = id == primaryID ? nil : id
        refresh(at: now)
    }

    // MARK: working it out

    private mutating func refresh(at now: Date) {
        let merged = mergedEntries()
        remember(merged, at: now)
        if let pinnedID, !merged.contains(where: { $0.id == pinnedID }) { self.pinnedID = nil }
        primaryID = choosePrimary(from: merged)
        if let selectedID, !merged.contains(where: { $0.id == selectedID }) || selectedID == primaryID { self.selectedID = nil }
        entries = merged.sorted(by: { isOrdered($0, before: $1) })
    }

    private func mergedEntries() -> [MediaSourceEntry] {
        var byID: [MediaSourceID: MediaSourceEntry] = [:]
        for (bundleID, state) in apps where !hiddenApps.contains(bundleID) {
            let id = MediaSourceID.app(bundleID)
            byID[id] = MediaSourceEntry(id: id, state: state, isSystemBacked: false, app: bundleID)
        }
        for (ref, session) in tabs {
            let id = MediaSourceID.tab(ref)
            byID[id] = MediaSourceEntry(id: id, state: session.state, isSystemBacked: false, tab: ref, site: session.site)
        }
        if let system {
            if system.isFromBrowser, let ref = tab(playing: system), var entry = byID[.tab(ref)] {
                entry.state = system.withArtwork(from: entry.state)
                entry.isSystemBacked = true
                byID[entry.id] = entry
            } else {
                // An app, or a browser that no tab accounts for (the extension is not there).
                let owner = system.playerBundleIdentifier ?? ""
                let id = MediaSourceID.app(owner)
                var entry = byID[id] ?? MediaSourceEntry(id: id, state: system, isSystemBacked: true, app: owner)
                entry.state = system.withArtwork(from: byID[id]?.state)
                entry.isSystemBacked = true
                byID[id] = entry
            }
        }
        return Array(byID.values)
    }

    /// The tab that plays what the system plays: the same title once normalised. Of several, one that plays, then the one heard from last.
    private func tab(playing system: NowPlayingState) -> TabRef? {
        guard let title = system.title else { return nil }
        let wanted = YouTubeCaptionMatcher.normalised(title)
        return tabs
            .filter { YouTubeCaptionMatcher.normalised($0.value.state.title ?? "") == wanted }
            .max { lhs, rhs in
                let left = (lhs.value.state.isPlaying ? 1 : 0, lhs.value.heardAt, lhs.key.tab)
                let right = (rhs.value.state.isPlaying ? 1 : 0, rhs.value.heardAt, rhs.key.tab)
                return left < right
            }?.key
    }

    private mutating func remember(_ merged: [MediaSourceEntry], at now: Date) {
        let live = Set(merged.map(\.id))
        playingSince = playingSince.filter { live.contains($0.key) }
        lastPlayed = lastPlayed.filter { live.contains($0.key) }
        firstSeen = firstSeen.filter { live.contains($0.key) }
        for entry in merged {
            if firstSeen[entry.id] == nil { firstSeen[entry.id] = now }
            if entry.isPlaying {
                if playingSince[entry.id] == nil { playingSince[entry.id] = now }
                lastPlayed[entry.id] = now
            } else {
                playingSince[entry.id] = nil
            }
        }
    }

    private func choosePrimary(from merged: [MediaSourceEntry]) -> MediaSourceID? {
        if let pinnedID, merged.contains(where: { $0.id == pinnedID }) { return pinnedID }
        let playing = merged.filter(\.isPlaying)
        if !playing.isEmpty { return playing.max { isLater($1, than: $0) }?.id }
        // Nothing plays: a pause never takes the place from the source that had it.
        if let primaryID, merged.contains(where: { $0.id == primaryID }) { return primaryID }
        return merged.max { isLater($1, than: $0) }?.id
    }

    /// `lhs` is the later of the two: of two that play, the one that began playing last; of two that do not, the one that played
    /// last, and of two that never played, the one seen first last. A tie goes to the system's session, then to the id, so that the
    /// choice does not depend on the order a dictionary lists them in.
    private func isLater(_ lhs: MediaSourceEntry, than rhs: MediaSourceEntry) -> Bool {
        let left = key(of: lhs)
        let right = key(of: rhs)
        if left != right { return left > right }
        return lhs.id.rawValue < rhs.id.rawValue
    }

    private func key(of entry: MediaSourceEntry) -> (began: Date, played: Date, seen: Date, system: Int) {
        (playingSince[entry.id] ?? .distantPast, lastPlayed[entry.id] ?? .distantPast, firstSeen[entry.id] ?? .distantPast, entry.isSystemBacked ? 1 : 0)
    }

    /// Chip order: the primary first (it is what the notch follows), then what plays, the most recent start first, then what is
    /// paused, the one that played last first.
    private func isOrdered(_ lhs: MediaSourceEntry, before rhs: MediaSourceEntry) -> Bool {
        if (lhs.id == primaryID) != (rhs.id == primaryID) { return lhs.id == primaryID }
        if lhs.isPlaying != rhs.isPlaying { return lhs.isPlaying }
        return isLater(lhs, than: rhs)
    }
}
