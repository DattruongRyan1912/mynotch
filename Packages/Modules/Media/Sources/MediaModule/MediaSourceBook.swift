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
///   source plays, and a source that goes away hands it on to the one playing, or else the one that was playing last. The place is
///   not taken from a source that plays by another that has only just started: it must stay the choice for `switchDelay` first, so
///   that a source cannot flap the notch. A page that has no element of ours and no sound Chrome hears never takes it by itself.
/// - **Shown** in the player: the source the user chose with a chip while it is there, else the primary.
/// - **A source that blinks.** The system's session is empty for a moment between two tracks, and a player's element is emptied at
///   the next video: that is not a source going away. What the user chose (the pin, the shown source), and the system's session that
///   has the notch while another source plays, are kept for `releaseGrace` after the source is missing, with the last state they had,
///   and released only when it has stayed away that long. Any source that goes keeps what was known of when it began to play for as
///   long, so that it comes back as it was and does not take the notch from the source that played meanwhile.
nonisolated struct MediaSourceBook: Sendable {
    /// A tab that has not been heard from for this long is not there any more. A page that plays reports every 5 s and a paused one
    /// every 30 s, but Chrome may let a tab it put to sleep stay quiet for a minute or two.
    static let tabLiveWindow: TimeInterval = 150
    /// How long a source the user pinned or chose may be missing before the choice is let go.
    static let releaseGrace: TimeInterval = 1.5
    /// How long another source must have been the choice for the primary to move to it from a source that plays.
    static let defaultSwitchDelay: TimeInterval = 1

    /// 0 moves the primary at once, for a test of the rules that is not about the delay.
    let switchDelay: TimeInterval

    init(switchDelay: TimeInterval = MediaSourceBook.defaultSwitchDelay) {
        self.switchDelay = switchDelay
    }

    private(set) var entries: [MediaSourceEntry] = []
    private(set) var primaryID: MediaSourceID?
    private(set) var pinnedID: MediaSourceID?
    private(set) var selectedID: MediaSourceID?

    private struct TabSession: Sendable {
        var state: NowPlayingState
        var site: String
        var heardAt: Date
        var isBelieved: Bool
    }

    /// A source the user chose that is missing now, as it was when it went, and since when.
    private struct Missing: Sendable {
        var entry: MediaSourceEntry
        var since: Date
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
    private var missing: [MediaSourceID: Missing] = [:]
    /// Since when a source that had a place in the memories above has not been there: it keeps them for `releaseGrace`, so that a source
    /// that blinks comes back as it was and is not taken for one that has just started.
    private var goneAt: [MediaSourceID: Date] = [:]
    /// The source that wants the primary place from one that plays, and since when.
    private var candidateID: MediaSourceID?
    private var candidateSince: Date?

    var primary: MediaSourceEntry? { primaryID.flatMap(entry(_:)) }

    /// What the player shows: the chosen source, else the primary.
    var displayedID: MediaSourceID? { selectedID ?? primaryID }
    var displayed: MediaSourceEntry? { displayedID.flatMap(entry(_:)) }

    func entry(_ id: MediaSourceID) -> MediaSourceEntry? { entries.first { $0.id == id } }

    /// The tab source with this reference, whether or not the system plays it.
    func entry(forTab ref: TabRef) -> MediaSourceEntry? { entry(.tab(ref)) }

    /// When the next tab will go stale or the next missing choice will be let go, so that one timer is enough; nil while there is none.
    var nextExpiry: Date? {
        let waiting = candidateSince.map { [$0 + switchDelay] } ?? []
        return (tabs.values.map { $0.heardAt + Self.tabLiveWindow } + missing.values.map { $0.since + Self.releaseGrace } + waiting).min()
    }

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
    /// `isBelieved`: an element of the page is the media, or Chrome hears the tab; a page that is neither does not take the notch by itself.
    mutating func setTab(_ ref: TabRef, state: NowPlayingState?, site: String = "", isBelieved: Bool = true, at now: Date) {
        tabs[ref] = state.map { TabSession(state: $0, site: site, heardAt: now, isBelieved: isBelieved) }
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

    /// Drops the tabs that have not been heard from for `tabLiveWindow`, and lets go of the choices whose source has been missing for
    /// `releaseGrace`.
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
        refresh(at: now, immediate: true)
    }

    mutating func unpin(at now: Date) {
        guard pinnedID != nil else { return }
        pinnedID = nil
        refresh(at: now, immediate: true)
    }

    mutating func togglePin(_ id: MediaSourceID, at now: Date) {
        if pinnedID == id { unpin(at: now) } else { pin(id, at: now) }
    }

    /// Show this source in the player. Choosing the primary is going back to following it.
    mutating func select(_ id: MediaSourceID, at now: Date) {
        guard entry(id) != nil else { return }
        selectedID = id == primaryID ? nil : id
        refresh(at: now, immediate: true)
    }

    // MARK: working it out

    /// - Parameter immediate: the user's own act (a pin, a chosen chip), which moves the primary place at once.
    private mutating func refresh(at now: Date, immediate: Bool = false) {
        var merged = mergedEntries()
        keepChoices(in: &merged, at: now)
        remember(merged, at: now)
        primaryID = resolvePrimary(choosePrimary(from: merged), in: merged, at: now, immediate: immediate)
        if let selectedID, selectedID == primaryID { self.selectedID = nil }
        entries = merged.sorted(by: { isOrdered($0, before: $1) })
    }

    /// The primary place moves to a source that plays only once that source has been the choice for `switchDelay`, when the one that has
    /// it plays too; the pin, the user's acts, and a place with nothing playing in it are not held.
    private mutating func resolvePrimary(_ desired: MediaSourceID?, in merged: [MediaSourceEntry], at now: Date, immediate: Bool) -> MediaSourceID? {
        guard !immediate, switchDelay > 0, let current = primaryID, let desired, desired != current, pinnedID != desired,
              merged.contains(where: { $0.id == current && $0.isPlaying })
        else {
            candidateID = nil
            candidateSince = nil
            return desired
        }
        if candidateID != desired {
            candidateID = desired
            candidateSince = now
        }
        guard let since = candidateSince, now.timeIntervalSince(since) >= switchDelay else { return current }
        candidateID = nil
        candidateSince = nil
        return desired
    }

    /// A source the user pinned or chose, or the one that has the notch while another source plays, that is missing stays, as it last was,
    /// until it has been missing for `releaseGrace`; one that comes back in time was never gone. What is none of those is gone at once.
    /// A pin or choice on a browser's own source that the extension then explains as a tab (or the reverse) follows the merge.
    private mutating func keepChoices(in merged: inout [MediaSourceEntry], at now: Date) {
        let live = Set(merged.map(\.id))
        var chosen = Set([pinnedID, selectedID].compactMap { $0 })
        // The notch's source, when it was the system's session that has gone while another source plays and the system has no other
        // session in its place (a session that moved to another app is a change of source, not a blink).
        if let primaryID, !live.contains(primaryID), merged.contains(where: { $0.isPlaying && $0.canLead }),
           let last = missing[primaryID]?.entry ?? entries.first(where: { $0.id == primaryID }), last.isPlaying, last.isSystemBacked,
           !merged.contains(where: { $0.isSystemBacked }) {
            chosen.insert(primaryID)
        }
        for id in missing.keys where live.contains(id) || !chosen.contains(id) { missing[id] = nil }
        for id in chosen where !live.contains(id) {
            let last = missing[id]?.entry ?? entries.first(where: { $0.id == id })
            if let last, let target = browserMerge(of: last, in: merged) {
                if pinnedID == id { pinnedID = target.id }
                if selectedID == id { selectedID = target.id }
                missing[id] = nil
            } else if let gone = missing[id] {
                if now.timeIntervalSince(gone.since) < Self.releaseGrace {
                    merged.append(gone.entry)
                } else {
                    release(id)
                }
            } else if let last {
                missing[id] = Missing(entry: last, since: now)
                merged.append(last)
            } else {
                release(id)
            }
        }
    }

    /// The source the system's session of a browser moved into: a tab where it was the browser's own, or the browser's own where it was a
    /// tab. Only the system's session can move so (another browser, or an app, is not a merge).
    private func browserMerge(of last: MediaSourceEntry, in merged: [MediaSourceEntry]) -> MediaSourceEntry? {
        guard last.isSystemBacked, last.state.isFromBrowser else { return nil }
        return merged.first {
            $0.isSystemBacked && $0.id != last.id && $0.state.isFromBrowser && $0.state.playerBundleIdentifier == last.state.playerBundleIdentifier
        }
    }

    private mutating func release(_ id: MediaSourceID) {
        if pinnedID == id { pinnedID = nil }
        if selectedID == id { selectedID = nil }
        missing[id] = nil
    }

    private func mergedEntries() -> [MediaSourceEntry] {
        var byID: [MediaSourceID: MediaSourceEntry] = [:]
        for (bundleID, state) in apps where !hiddenApps.contains(bundleID) {
            let id = MediaSourceID.app(bundleID)
            byID[id] = MediaSourceEntry(id: id, state: state, isSystemBacked: false, app: bundleID)
        }
        for (ref, session) in tabs {
            let id = MediaSourceID.tab(ref)
            byID[id] = MediaSourceEntry(id: id, state: session.state, isSystemBacked: false, tab: ref, site: session.site, canLead: session.isBelieved)
        }
        if let system {
            if system.isFromBrowser, let ref = tab(playing: system), var entry = byID[.tab(ref)] {
                entry.state = system.withArtwork(from: entry.state)
                entry.isSystemBacked = true
                entry.canLead = true // the system says it plays
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
    /// Failing that, when the titles differ (a page and Chrome may word one title two ways, and they differ for a moment as a video
    /// changes) the one tab that plays, if exactly one does and it could be the same media: a browser session no tab explains is rather
    /// that tab than a second chip. It could not when the system's session is paused while the tab plays, or when their lengths are
    /// plainly not the same: that is a page the extension cannot see (a video in a frame of another site) next to the tab that plays,
    /// two sources that one chip would hide.
    private func tab(playing system: NowPlayingState) -> TabRef? {
        guard let title = system.title else { return nil }
        let wanted = YouTubeCaptionMatcher.normalised(title)
        let same = tabs
            .filter { YouTubeCaptionMatcher.normalised($0.value.state.title ?? "") == wanted }
            .max { lhs, rhs in
                let left = (lhs.value.state.isPlaying ? 1 : 0, lhs.value.heardAt, lhs.key.tab)
                let right = (rhs.value.state.isPlaying ? 1 : 0, rhs.value.heardAt, rhs.key.tab)
                return left < right
            }
        if let same { return same.key }
        let playing = tabs.filter { $0.value.state.isPlaying }
        guard playing.count == 1, let only = playing.first, Self.couldBeTheSame(system, only.value.state) else { return nil }
        return only.key
    }

    /// Lengths further apart than this are two media, not one told two ways.
    static let durationTolerance: TimeInterval = 5

    /// Whether a playing tab whose title differs from the system's session could still be what that session plays.
    static func couldBeTheSame(_ system: NowPlayingState, _ tab: NowPlayingState) -> Bool {
        guard system.isPlaying == tab.isPlaying else { return false }
        guard let left = system.durationSeconds, let right = tab.durationSeconds, left > 0, right > 0 else { return true }
        return abs(left - right) <= durationTolerance
    }

    private mutating func remember(_ merged: [MediaSourceEntry], at now: Date) {
        let live = Set(merged.map(\.id))
        // A source that is missing keeps what was known of it for `releaseGrace`, and is then forgotten.
        let remembered = Set(playingSince.keys).union(lastPlayed.keys).union(firstSeen.keys)
        for id in remembered where !live.contains(id) {
            let since = goneAt[id] ?? now
            goneAt[id] = since
            if now.timeIntervalSince(since) >= Self.releaseGrace { forget(id) }
        }
        for entry in merged {
            // A source back after longer than the grace is a new one.
            if let since = goneAt[entry.id] {
                goneAt[entry.id] = nil
                if now.timeIntervalSince(since) >= Self.releaseGrace { forget(entry.id) }
            }
            if firstSeen[entry.id] == nil { firstSeen[entry.id] = now }
            if entry.isPlaying {
                if playingSince[entry.id] == nil { playingSince[entry.id] = now }
                lastPlayed[entry.id] = now
            } else {
                playingSince[entry.id] = nil
            }
        }
    }

    private mutating func forget(_ id: MediaSourceID) {
        playingSince[id] = nil
        lastPlayed[id] = nil
        firstSeen[id] = nil
        goneAt[id] = nil
    }

    private func choosePrimary(from merged: [MediaSourceEntry]) -> MediaSourceID? {
        if let pinnedID, merged.contains(where: { $0.id == pinnedID }) { return pinnedID }
        let leaders = merged.filter(\.canLead)
        let playing = leaders.filter(\.isPlaying)
        if !playing.isEmpty { return playing.max { isLater($1, than: $0) }?.id }
        // Nothing plays: a pause never takes the place from the source that had it.
        if let primaryID, merged.contains(where: { $0.id == primaryID }) { return primaryID }
        return leaders.max { isLater($1, than: $0) }?.id
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
