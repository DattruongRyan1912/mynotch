import Foundation
import MyNotchCore
import YouTubeBridgeKit

/// Puts the sources of sound together: what the system says is playing, Music and Spotify (by their own notifications, and by Apple
/// Events once the user lets MyNotch), and the tabs of Chrome (by the extension). It keeps the `MediaSourceBook`, which works out
/// the chips, the primary source and the one the player shows, and tells the module whenever that changes.
///
/// What it costs: the notifications and the extension's reports are events, and nothing else runs while the Media tab is hidden and the
/// notch is not following an app, playing, that only Apple Events can read; one timer, once a second, reads the apps when it is, or
/// when the tab is on screen, and another sleeps until the next tab goes stale.
///
/// What it asks of the user, and when: Apple Events need the user's say (Automation). It is asked for an app the first time the user
/// takes that app's chip or presses one of its controls, never at launch. An app the user refused is not shown from what it says of
/// itself (the system's own session for it still is), and Settings says so.
final class MediaSourceHub {
    /// What changed, for the module: the system's session (every line of it is news, as it always was) or anything else.
    enum Change {
        case system
        case other
    }

    /// How often the apps are read while that is needed.
    static let pollInterval: Duration = .seconds(1)
    /// The browser the extension lives in: the host's manifest is written for Chrome only.
    static let browserBundleID = "com.google.Chrome"
    /// A position that is within this many seconds of where the last report put it is not news.
    static let positionTolerance = 0.5

    let model = MediaSourceModel()
    private(set) var book = MediaSourceBook()
    /// The module hears of every change after the chips are up to date.
    var onChange: (Change) -> Void = { _ in }

    private let environment: MediaAppEnvironment
    private let controls: [String: any AppPlayerControl]
    private var scheduler: (any Scheduler)?
    private var permissions: (any PermissionCenter)?
    private var now: () -> Date

    private var sessions: [String: AppPlayerSession] = [:]
    private var tabStates: [TabRef: NowPlayingState] = [:]
    private var artworkRevision = 0
    /// Apps the user let control (read, then, by Apple Events) and apps they refused, by bundle id.
    private var granted: Set<String> = []
    private var denied: Set<String> = []
    /// Apps already asked, so that the question is put once, and reads that are not finished.
    private var asked: Set<String> = []
    private var inFlight: Set<String> = []
    private var cancellations: [() -> Void] = []
    private var pollTimer: ScheduledAction?
    private var expiryTimer: ScheduledAction?
    private var scheduledExpiry: Date?
    /// Counts starts, so that an answer that was on its way when the module stopped finds out it is stale.
    private var generation = 0

    init(environment: MediaAppEnvironment = .inert, controls: [any AppPlayerControl] = [], now: @escaping () -> Date = Date.init) {
        self.environment = environment
        self.controls = Dictionary(uniqueKeysWithValues: controls.map { ($0.player.bundleID, $0) })
        self.now = now
        model.onSelect = { [weak self] in self?.select($0) }
        model.onTogglePin = { [weak self] in self?.togglePin($0) }
        model.onVisibilityChange = { [weak self] in self?.visibilityChanged($0) }
    }

    func start(scheduler: any Scheduler, permissions: any PermissionCenter) {
        stop()
        self.scheduler = scheduler
        self.permissions = permissions
        generation += 1
        for player in KnownPlayer.allCases where controls[player.bundleID] != nil {
            cancellations.append(environment.observe(player.notificationName) { [weak self] info in self?.notified(player, info) })
        }
        cancellations.append(environment.observeQuit { [weak self] bundleID in self?.quit(bundleID) })
        refreshPermissions()
        publish(.other)
    }

    /// Everything goes: the observers, the timers, what the sources said and what the user chose.
    func stop() {
        generation += 1
        for cancel in cancellations { cancel() }
        cancellations = []
        pollTimer?.cancel()
        pollTimer = nil
        expiryTimer?.cancel()
        expiryTimer = nil
        scheduledExpiry = nil
        scheduler = nil
        permissions = nil
        sessions = [:]
        tabStates = [:]
        granted = []
        denied = []
        asked = []
        inFlight = []
        book = MediaSourceBook()
        model.reset()
    }

    // MARK: what the sources report

    func setSystem(_ state: NowPlayingState?) {
        book.setSystem(state, at: now())
        publish(.system)
    }

    /// A page with media reported, on connection `connection` (the Chrome profile).
    func receive(_ tab: BrowserTab, connection: Int) {
        let date = now()
        let ref = TabRef(connection: connection, tab: tab.tab)
        let state = Self.state(of: tab, replacing: tabStates[ref], at: date)
        tabStates[ref] = state
        book.setTab(ref, state: state, site: tab.site, at: date)
        publish(.other)
    }

    func tabGone(_ tab: Int, connection: Int) {
        let ref = TabRef(connection: connection, tab: tab)
        guard tabStates.removeValue(forKey: ref) != nil else { return }
        book.setTab(ref, state: nil, at: now())
        publish(.other)
    }

    /// The bridge is off: no page is heard from.
    func forgetTabs() {
        guard !tabStates.isEmpty else { return }
        tabStates = [:]
        book.removeAllTabs(at: now())
        publish(.other)
    }

    /// The Chrome behind `connection` has gone.
    func connectionEnded(_ connection: Int) {
        guard tabStates.keys.contains(where: { $0.connection == connection }) else { return }
        tabStates = tabStates.filter { $0.key.connection != connection }
        book.removeTabs(ofConnection: connection, at: now())
        publish(.other)
    }

    /// What a page says, as the player shows it: the browser plays it; its artist is the site when the page names none.
    static func state(of tab: BrowserTab, replacing previous: NowPlayingState?, at date: Date) -> NowPlayingState {
        var anchor = PlaybackAnchor(elapsedSeconds: tab.time, timestamp: date, rate: tab.isPlaying ? tab.rate : 0)
        var state = NowPlayingState(
            bundleIdentifier: browserBundleID, parentApplicationBundleIdentifier: browserBundleID, title: tab.title,
            artist: tab.artist ?? (tab.site.isEmpty ? nil : tab.site), album: tab.album, durationSeconds: tab.duration.flatMap { $0 > 0 ? $0 : nil },
            isPlaying: tab.isPlaying
        )
        // A report that puts the position where the last one's anchor already has it changes nothing: a page reports every few
        // seconds, and each report would otherwise redraw the player.
        if let previous, let before = previous.elapsedAnchor, previous.title == state.title, previous.isPlaying == state.isPlaying,
           before.rate == anchor.rate, previous.durationSeconds == state.durationSeconds, previous.artist == state.artist,
           let expected = PlaybackClock.position(previous, at: date), abs(expected - tab.time) < positionTolerance {
            anchor = before
        }
        state.elapsedAnchor = anchor
        return state
    }

    // MARK: players: notifications

    private func notified(_ player: KnownPlayer, _ info: [AnyHashable: Any]) {
        guard let event = player.event(fromNotification: info) else { return }
        let bundleID = player.bundleID
        switch event {
        case .stopped:
            removeApp(bundleID)
        case .track(let snapshot):
            let session = AppPlayerSession(notified: snapshot, replacing: sessions[bundleID], at: now(), revision: nextRevision)
            setSession(session, for: bundleID, keepingAnchorOf: sessions[bundleID])
        }
    }

    private func quit(_ bundleID: String) {
        guard sessions[bundleID] != nil else { return }
        removeApp(bundleID)
    }

    private func removeApp(_ bundleID: String) {
        guard sessions.removeValue(forKey: bundleID) != nil else { return }
        book.setApp(bundleID, state: nil, at: now())
        publish(.other)
    }

    private func nextRevision() -> Int {
        artworkRevision += 1
        return artworkRevision
    }

    /// Puts an app's session in the book. A session whose position is where the earlier one's anchor already has it keeps that
    /// anchor, so that a read every second that finds the player where it was changes nothing the views see.
    private func setSession(_ session: AppPlayerSession, for bundleID: String, keepingAnchorOf previous: AppPlayerSession?) {
        var session = session
        if let previous, let before = previous.anchor, let anchor = session.anchor, previous.snapshot.isSameTrack(as: session.snapshot),
           previous.snapshot.isPlaying == session.snapshot.isPlaying, before.rate == anchor.rate {
            let expected = before.elapsedSeconds + (previous.snapshot.isPlaying ? anchor.timestamp.timeIntervalSince(before.timestamp) * before.rate : 0)
            if abs(expected - anchor.elapsedSeconds) < Self.positionTolerance { session.anchor = before }
        }
        guard session != sessions[bundleID] else { return }
        sessions[bundleID] = session
        book.setApp(bundleID, state: session.state(bundleID: bundleID), at: now())
        publish(.other)
    }

    // MARK: players: Apple Events

    /// Whether macOS lets MyNotch control the app: allowed apps are read and controlled, refused ones are hidden and named in Settings.
    /// An app that is not running has no answer to give, so nothing changes for it.
    private func refreshPermissions() {
        guard let permissions else { return }
        for bundleID in controls.keys {
            switch permissions.status(of: .automation(bundleID: bundleID)) {
            case .granted: markGranted(bundleID, publishing: false)
            case .denied: markDenied(bundleID, publishing: false)
            case .notDetermined, .unknown: break
            }
        }
    }

    private func markGranted(_ bundleID: String, publishing: Bool = true) {
        granted.insert(bundleID)
        denied.remove(bundleID)
        book.setHidden(bundleID, false, at: now())
        if publishing { publish(.other) }
    }

    private func markDenied(_ bundleID: String, publishing: Bool = true) {
        granted.remove(bundleID)
        denied.insert(bundleID)
        book.setHidden(bundleID, true, at: now())
        if publishing { publish(.other) }
    }

    /// Whether the app may be read and controlled, asking the user the first time (it is only ever asked once per run, and macOS
    /// remembers the answer). False while the app is not running, since there is no one to ask about.
    private func ensureAllowed(_ bundleID: String) async -> Bool {
        guard let permissions, controls[bundleID] != nil, environment.isRunning(bundleID) else { return false }
        switch permissions.status(of: .automation(bundleID: bundleID)) {
        case .granted:
            markGranted(bundleID)
            return true
        case .denied:
            markDenied(bundleID)
            return false
        case .unknown:
            return false
        case .notDetermined:
            guard asked.insert(bundleID).inserted else { return false }
            let generation = generation
            let answer = await permissions.request(.automation(bundleID: bundleID))
            guard generation == self.generation else { return false }
            switch answer {
            case .granted:
                markGranted(bundleID)
                return true
            case .denied:
                markDenied(bundleID)
                return false
            case .notDetermined, .unknown:
                return false
            }
        }
    }

    /// An app that Apple Events have to read, now: it runs, the user let MyNotch, the system does not already say all there is to
    /// know (its session for the app is the source), and someone looks: the Media tab is open, or the notch follows that app.
    private func pollTargets() -> [any AppPlayerControl] {
        controls.values.filter { control in
            let bundleID = control.player.bundleID
            guard granted.contains(bundleID), !denied.contains(bundleID), environment.isRunning(bundleID) else { return false }
            if book.entry(.app(bundleID))?.isSystemBacked == true { return false }
            // The notch follows it and it plays: its position is what changes, and nothing else tells it. A paused one says when it
            // plays again (its own notification), so a hidden tab costs nothing then.
            let isFollowed = book.primaryID == .app(bundleID) && book.primary?.isPlaying == true
            return model.isTabVisible || isFollowed
        }
    }

    private func refreshPolling() {
        guard scheduler != nil else { return }
        if pollTargets().isEmpty {
            pollTimer?.cancel()
            pollTimer = nil
        } else if pollTimer == nil {
            armPoll()
        }
    }

    private func armPoll() {
        pollTimer = scheduler?.schedule(after: Self.pollInterval) { [weak self] in self?.pollFired() }
    }

    private func pollFired() {
        pollTimer = nil
        let targets = pollTargets()
        guard !targets.isEmpty else { return }
        for control in targets { read(control) }
        armPoll()
    }

    private func read(_ control: any AppPlayerControl) {
        let bundleID = control.player.bundleID
        guard inFlight.insert(bundleID).inserted else { return }
        let generation = generation
        Task { [weak self] in
            let reading = await control.read()
            self?.finishRead(reading, from: bundleID, generation: generation)
        }
    }

    private func finishRead(_ reading: AppPlayerReading, from bundleID: String, generation: Int) {
        guard generation == self.generation else { return }
        inFlight.remove(bundleID)
        switch reading {
        case .snapshot(let snapshot):
            let previous = sessions[bundleID]
            setSession(AppPlayerSession(read: snapshot, replacing: previous, at: now(), revision: nextRevision), for: bundleID, keepingAnchorOf: previous)
        case .stopped, .notRunning:
            removeApp(bundleID)
        case .notAllowed:
            markDenied(bundleID)
        case .failed:
            break
        }
    }

    /// Asks an app to do something, after asking the user the first time. Next, a read, so that the player shows what it did.
    func perform(_ command: AppPlayerCommand, onApp bundleID: String) {
        guard let control = controls[bundleID] else { return }
        let generation = generation
        Task { [weak self] in
            guard let self, await ensureAllowed(bundleID), generation == self.generation, environment.isRunning(bundleID) else { return }
            let outcome = await control.perform(command)
            guard generation == self.generation else { return }
            switch outcome {
            case .done: read(control)
            case .notAllowed: markDenied(bundleID)
            case .notRunning: removeApp(bundleID)
            case .failed: break
            }
        }
    }

    // MARK: what the user does

    func select(_ id: MediaSourceID) {
        book.select(id, at: now())
        // The first time the user takes an app's chip is the first time MyNotch has a reason to ask about it.
        if let entry = book.entry(id), !entry.isSystemBacked, let bundleID = entry.app, controls[bundleID] != nil {
            Task { [weak self] in _ = await self?.ensureAllowed(bundleID) }
        }
        publish(.other)
    }

    func togglePin(_ id: MediaSourceID) {
        book.togglePin(id, at: now())
        publish(.other)
    }

    /// The Media tab appeared or went away. Looking at it is a reason to read the apps, and to see again what macOS says of them.
    private func visibilityChanged(_ isVisible: Bool) {
        if isVisible {
            refreshPermissions()
            publish(.other)
            for control in pollTargets() { read(control) }
        }
        refreshPolling()
    }

    // MARK: keeping up

    /// The chips and the model are up to date, the timers are what is needed now, and the module is told.
    private func publish(_ change: Change) {
        model.update(chips: book.entries.map(chip(for:)), displayedID: book.displayedID, primaryID: book.primaryID)
        model.setDeniedApps(KnownPlayer.allCases.filter { denied.contains($0.bundleID) }.map(\.name))
        scheduleExpiry()
        refreshPolling()
        onChange(change)
    }

    private func chip(for entry: MediaSourceEntry) -> MediaSourceChip {
        MediaSourceChip(
            id: entry.id, title: entry.state.title ?? "", detail: entry.site ?? entry.state.artist ?? "", isPlaying: entry.isPlaying,
            isPrimary: entry.id == book.primaryID, isPinned: entry.id == book.pinnedID, isShown: entry.id == book.displayedID,
            iconBundleID: entry.state.playerBundleIdentifier
        )
    }

    /// One timer, for the tab that will go stale first.
    private func scheduleExpiry() {
        guard book.nextExpiry != scheduledExpiry else { return }
        expiryTimer?.cancel()
        expiryTimer = nil
        scheduledExpiry = nil
        guard let deadline = book.nextExpiry, let scheduler else { return }
        scheduledExpiry = deadline
        let delay = Duration.milliseconds(Int64((max(deadline.timeIntervalSince(now()), 0) * 1000).rounded(.up)))
        expiryTimer = scheduler.schedule(after: delay) { [weak self] in self?.expire() }
    }

    private func expire() {
        expiryTimer = nil
        scheduledExpiry = nil
        // The timer may fire a little early after rounding; the deadline itself is when the book expects the tick.
        book.expireTabs(at: max(now(), book.nextExpiry ?? now()))
        tabStates = tabStates.filter { book.entry(forTab: $0.key) != nil }
        publish(.other)
    }
}
