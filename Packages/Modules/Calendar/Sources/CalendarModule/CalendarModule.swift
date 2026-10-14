import AppKit
import MyNotchCore
import Observation
import SwiftUI

/// What the tab's buttons do, without handing the views the module.
struct CalendarActions {
    var open: (AgendaEvent) -> Void
    var join: (AgendaEvent) -> Void
    var dismiss: (AgendaEvent) -> Void
    var complete: (AgendaReminder) -> Void
    var requestRemindersAccess: () -> Void
    /// The tab came on screen: access may have changed in Settings while it was away.
    var appeared: () -> Void
}

/// Opens a URL for the user and says whether something took it. Injected so tests never launch an app or a browser.
typealias URLOpener = @MainActor (URL) -> Bool

/// Today's events and reminders in a tab, and a live activity that counts down to the next meeting.
public final class CalendarModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "calendar",
        displayName: "Lịch",
        systemImage: "calendar",
        defaultEnabled: true,
        permissions: [.calendars],
        optionalPermissions: [.reminders],
        permissionReasons: [
            .calendars: "Hiện sự kiện sắp tới và thông báo họp.",
            .reminders: "Hiện lời nhắc khi bật “Hiện lời nhắc đến hạn hôm nay”.",
        ],
        order: 600
    )

    static let activityID = "meeting"
    /// Past the minute boundary, so a timer that fires a hair early still reads the new minute.
    static let minuteMargin = Duration.milliseconds(100)
    /// Waits for a burst of wakes and day changes to settle before reading the calendar again. Changes in the
    /// calendar need no wait here: the data source has already let them settle.
    static let refreshDebounce = Duration.seconds(1)

    let state: CalendarState
    private let dataSource: any CalendarDataSource
    private let clock: () -> Date
    private let calendar: Calendar
    private let openURL: URLOpener
    private let dayChangeCenter: NotificationCenter
    private let wakeCenter: NotificationCenter
    private var context: ModuleContext?
    private var policy = UpcomingMeetingPolicy(leadMinutes: 5)
    /// The settings the latest refresh used; a settings write that leaves them as they are needs no refresh.
    private var usedSettings: CalendarSettings?
    private var minuteTimer: ScheduledAction?
    private var debounce: ScheduledAction?
    /// Only the newest refresh applies its result: an older one may have read the calendar before a change.
    private var refreshGeneration = 0
    /// Reminders the user has ticked whose save hasn't finished: hidden, so a refresh doesn't bring them back early.
    private var completing: Set<String> = []
    /// Number of refreshes whose result was applied, and of requests for one; tests wait on them.
    private(set) var appliedRefreshes = 0
    private(set) var refreshRequests = 0
    /// What the activity shows now; nil while none is published.
    private(set) var publishedMeeting: MeetingActivityContent?
    /// How long the pending minute timer was set for; tests move the clock by it.
    private(set) var minuteTimerDelay = Duration.zero

    public convenience init() {
        self.init(dataSource: CalendarService())
    }

    /// Tests pass fakes: no EventKit, no real clock, no notification of the system and nothing opened.
    init(
        dataSource: any CalendarDataSource,
        now: @escaping () -> Date = { .now },
        calendar: Calendar = .autoupdatingCurrent,
        openURL: @escaping URLOpener = { NSWorkspace.shared.open($0) },
        dayChangeCenter: NotificationCenter = .default,
        wakeCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.dataSource = dataSource
        self.clock = now
        self.calendar = calendar
        self.openURL = openURL
        self.dayChangeCenter = dayChangeCenter
        self.wakeCenter = wakeCenter
        state = CalendarState(now: now(), calendar: calendar)
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        self.context = context
        let settings = CalendarSettings(context.settings)
        usedSettings = settings
        policy = UpcomingMeetingPolicy(leadMinutes: settings.meetingLeadMinutes)
        // Each source is asked for its stream here, not in the loop that reads it, so nothing that happens
        // from now on is missed while that loop is still getting started.
        refreshOn(dataSource.changes, debounced: false)
        refreshOn(Self.signals(named: .NSCalendarDayChanged, in: dayChangeCenter), debounced: true)
        refreshOn(Self.signals(named: NSWorkspace.didWakeNotification, in: wakeCenter), debounced: true)
        let moduleSettings = context.settings
        context.run { [weak self] in
            for await _ in Observations({ CalendarSettings(moduleSettings) }) { self?.settingsChanged() }
        }
        scheduleMinuteTimer()
        startRefresh()
    }

    public func stop() async {
        minuteTimer?.cancel()
        minuteTimer = nil
        debounce?.cancel()
        debounce = nil
        context = nil
        refreshGeneration += 1
        completing = []
        publishedMeeting = nil
        policy = UpcomingMeetingPolicy(leadMinutes: policy.leadMinutes)
        state.reset()
    }

    public func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id, title: "Lịch", systemImage: "calendar", preferredHeight: 220,
            content: AnyView(CalendarTabView(state: state, actions: actions))
        )
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        let dataSource = dataSource
        return AnyView(CalendarSettingsView(
            settings: environment.settings,
            keys: CalendarSettingsKeys(environment.settings),
            permissions: environment.permissions,
            loadCalendars: { await dataSource.calendars() },
            remindersAccessAnswered: { [weak self] in self?.startRefresh() }
        ))
    }

    var actions: CalendarActions {
        CalendarActions(
            open: { [weak self] event in self?.open(event) },
            join: { [weak self] event in self?.join(event) },
            dismiss: { [weak self] event in self?.dismissMeeting(event) },
            complete: { [weak self] reminder in self?.context?.run { await self?.complete(reminder) } },
            requestRemindersAccess: { [weak self] in self?.context?.run { await self?.requestRemindersAccess() } },
            appeared: { [weak self] in self?.tabAppeared() }
        )
    }

    // MARK: Actions used by the tab

    /// Calendar opens the event; if it can't be told which, it still opens.
    func open(_ event: AgendaEvent) {
        if let url = CalendarLinks.eventURL(calendarItemIdentifier: event.calendarItemIdentifier), openURL(url) { return }
        _ = openURL(CalendarLinks.calendarApp)
    }

    /// Opens the meeting link. Joining ends the countdown, but only once something actually took the link.
    func join(_ event: AgendaEvent) {
        guard let url = event.meetingURL, openURL(url) else { return }
        dismissMeeting(event)
    }

    func dismissMeeting(_ event: AgendaEvent) {
        policy = policy.dismissed(eventID: event.id)
        updateMeeting(now: clock())
    }

    /// Ticks the reminder off in the data source, then reads the list again: a save that failed brings it back.
    func complete(_ reminder: AgendaReminder) async {
        hideCompleting(reminder)
        do {
            try await dataSource.complete(reminderID: reminder.id)
        } catch {
            context?.logger.error("Could not complete a reminder: \(String(describing: error), privacy: .public)")
        }
        completing.remove(reminder.id)
        await refresh()
    }

    /// Takes the reminder off the list at once instead of after the save.
    func hideCompleting(_ reminder: AgendaReminder) {
        completing.insert(reminder.id)
        if case .items(let items) = state.reminders {
            state.reminders = .items(items.filter { $0.id != reminder.id })
        }
    }

    func requestRemindersAccess() async {
        guard let context else { return }
        await RemindersAccess(permissions: context.permissions).request(openSettingsIfDenied: true)
        await refresh()
    }

    /// Nothing tells the module when Reminders access changes in Settings, so the tab checks when it opens.
    func tabAppeared() {
        guard let context, state.remindersAreStale(granted: context.permissions.status(of: .reminders) == .granted) else { return }
        startRefresh()
    }

    // MARK: Refreshing

    func refresh() async {
        guard let context else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let now = clock()
        let settings = CalendarSettings(context.settings)
        usedSettings = settings
        let range = AgendaBuilder.fetchRange(now: now, calendar: calendar)
        let events = await dataSource.events(from: range.start, to: range.end)
        var reminders: [AgendaReminder]?
        if settings.showReminders, context.permissions.status(of: .reminders) == .granted {
            let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? range.start
            reminders = await dataSource.reminders(dueBy: endOfToday)
        }
        guard generation == refreshGeneration, self.context === context else { return }
        apply(events: events, reminders: reminders, settings: settings, now: now)
    }

    private func apply(events: [AgendaEvent], reminders: [AgendaReminder]?, settings: CalendarSettings, now: Date) {
        policy.leadMinutes = settings.meetingLeadMinutes
        let hidden = Set(settings.hiddenCalendarIDs)
        let shown = events.filter { !hidden.contains($0.calendarID) && (settings.showAllDay || !$0.isAllDay) }
        let agenda = AgendaBuilder.build(events: shown, now: now, calendar: calendar)
        if state.now != now { state.now = now }
        if state.agenda != agenda { state.agenda = agenda }
        let section = remindersSection(reminders, settings: settings)
        if state.reminders != section { state.reminders = section }
        appliedRefreshes += 1
        updateMeeting(now: now)
    }

    private func remindersSection(_ reminders: [AgendaReminder]?, settings: CalendarSettings) -> RemindersSection {
        guard settings.showReminders else { return .hidden }
        guard let reminders else { return .needsAccess }
        let open = reminders.filter { !completing.contains($0.id) }
        return .items(AgendaReminder.sortedByDue(open, calendar: calendar))
    }

    /// Reads the calendar again, after a quiet second if the trigger can come in bursts.
    private func requestRefresh(debounced: Bool) {
        guard let context else { return }
        refreshRequests += 1
        guard debounced else { return startRefresh() }
        debounce?.cancel()
        debounce = context.scheduler.schedule(after: Self.refreshDebounce) { [weak self] in
            self?.debounce = nil
            self?.startRefresh()
        }
    }

    private func startRefresh() {
        context?.run { [weak self] in await self?.refresh() }
    }

    private func refreshOn(_ stream: AsyncStream<Void>, debounced: Bool) {
        context?.run { [weak self] in
            for await _ in stream { self?.requestRefresh(debounced: debounced) }
        }
    }

    /// The countdown is only right if the agenda is read again every minute, so the timer aims for the next minute
    /// boundary: the activity changes as the clock does, and a late timer doesn't push every later one off.
    private func scheduleMinuteTimer() {
        let intoMinute = clock().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60)
        minuteTimerDelay = .milliseconds(Int(((60 - intoMinute) * 1000).rounded())) + Self.minuteMargin
        minuteTimer = context?.scheduler.schedule(after: minuteTimerDelay) { [weak self] in
            self?.scheduleMinuteTimer()
            self?.startRefresh()
        }
    }

    private func settingsChanged() {
        guard let context, CalendarSettings(context.settings) != usedSettings else { return }
        startRefresh()
    }

    /// The observer is added when the stream is made, and its token goes when the stream ends.
    private static func signals(named name: Notification.Name, in center: NotificationCenter) -> AsyncStream<Void> {
        let (stream, input) = AsyncStream<Void>.makeStream()
        let observer = ObserverToken(center.addObserver(forName: name, object: nil, queue: nil) { _ in input.yield() })
        input.onTermination = { _ in center.removeObserver(observer.token) }
        return stream
    }

    // MARK: Meeting activity

    /// Sets the activity when its content changes and clears it when it hides, so it is updated at most once a minute.
    private func updateMeeting(now: Date) {
        guard let context else { return }
        // The activity looks past midnight: a meeting at 00:10 shows at 23:40. The card prefers what's left of today.
        let upcoming = state.agenda.upcoming
        let content = MeetingActivityContent(event: policy.nextMeeting(in: upcoming, now: now), policy: policy, now: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let featured = policy.nextMeeting(in: upcoming.filter { $0.start < endOfToday }, now: now, includingDismissed: true)
            ?? state.agenda.next
        if state.featured != featured { state.featured = featured }
        let canDismiss = content != nil && content?.eventID == featured?.id
        if state.canDismissFeatured != canDismiss { state.canDismissFeatured = canDismiss }
        guard content != publishedMeeting else { return }
        publishedMeeting = content
        if let content {
            context.activities.set(content.liveActivity)
        } else {
            context.activities.clear(id: Self.activityID)
        }
    }
}

/// `NSObjectProtocol` observer tokens aren't `Sendable`, but removing one from any thread is safe.
private nonisolated final class ObserverToken: @unchecked Sendable {
    let token: any NSObjectProtocol

    init(_ token: any NSObjectProtocol) {
        self.token = token
    }
}
