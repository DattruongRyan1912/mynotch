import AppKit
import MyNotchCore
import Observation
import SwiftUI

/// What the tab's buttons do, without handing the views the module.
struct TodoActions {
    var complete: (String) -> Void
    var undo: (String) -> Void
    var moveToQuadrant: (String, EisenhowerQuadrant) -> Void = { _, _ in }
    /// Return in the field: whether a reminder was saved, so the field knows to clear.
    var add: (String) async -> Bool
    var requestAccess: () -> Void
    /// "Thử lại": the last read failed.
    var retry: () -> Void
    /// Runs while the access hint is on screen, and reads again the moment access appears: nothing re-mounts a tab that
    /// is already open when it is granted elsewhere.
    var watchAccess: () async -> Void
    /// The tab came on screen: access or the day may have changed while it was away.
    var appeared: () -> Void
}

/// A daily checklist in a tab: today's reminders, and the ones left over from earlier days, kept in Apple Reminders.
public final class TodoModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "todo",
        displayName: "Việc cần làm",
        systemImage: "checklist",
        defaultEnabled: true,
        // Optional, so the tab exists from the first run and asks from there: a required permission would keep the module
        // (and its tab) from starting until it was granted in Settings.
        optionalPermissions: [.reminders],
        permissionReasons: [.reminders: "Đọc, thêm và đánh dấu xong các việc trong Lời nhắc."],
        order: 650
    )

    static let activityID = "remaining"
    /// ⌃⌥D opens the tab; ⌃⌥⇧D opens it with the field ready. Neither is another module's default.
    static let openShortcut = KeyboardShortcuts.Shortcut(.d, modifiers: [.control, .option])
    static let quickAddShortcut = KeyboardShortcuts.Shortcut(.d, modifiers: [.control, .option, .shift])
    /// How long a ticked-off row stays, struck through, with "Hoàn tác".
    static let lingerDuration = Duration.seconds(2)
    /// How long the line under the field stays.
    static let noticeDuration = Duration.seconds(3)
    /// How long the quick-add shortcut's request for the field waits for the tab to show it. A notch that never opened (a full
    /// screen app, say) must not leave the request to be served by some later, unrelated open.
    static let focusRequestLifetime = Duration.seconds(2)
    /// After the prompt is answered the system can go on saying "not determined" for a moment, so the status is read again
    /// every 100 ms for up to 2 s before the answer is believed.
    static let defaultAccessRecheck = (interval: Duration.milliseconds(100), limit: Duration.seconds(2))
    /// Waits for a burst of wakes and day changes to settle before reading again. Changes in Reminders need no wait here:
    /// the data source has already let them settle.
    static let refreshDebounce = Duration.seconds(1)

    let state: TodoState
    private let dataSource: any TodoDataSource
    private let clock: () -> Date
    private let calendar: Calendar
    private let dayChangeCenter: NotificationCenter
    private let wakeCenter: NotificationCenter
    private let activeCenter: NotificationCenter
    private let accessRecheck: (interval: Duration, limit: Duration)
    private let accessWatchInterval: Duration
    private var context: ModuleContext?
    /// The settings the latest refresh used; a settings write that leaves them as they are needs no refresh.
    private var usedSettings: TodoSettings?
    private var debounce: ScheduledAction?
    /// Only the newest refresh applies its result: an older one may have read Reminders before a change.
    private var refreshGeneration = 0
    /// What was last read from Reminders, and when, before the user's ticks are laid over it. The list is built from this
    /// again whenever a tick changes it, with no read.
    private var read: [TodoReminder] = []
    private var readAt: Date
    private var rules = TodoRules()
    /// Ticks and undos whose save hasn't finished: what the user asked for wins over what was read, so a read made
    /// in between doesn't bring a row back. `serial` tells a later request for the same reminder from an earlier one.
    private var wanted: [String: Want] = [:]
    private var wantSerial = 0
    private var lingerTimers: [String: ScheduledAction] = [:]
    private var noticeTimer: ScheduledAction?
    private var focusTimer: ScheduledAction?
    private var isAdding = false
    private var inFlightQuadrantMoves: Set<String> = []
    /// Access was found missing and has not been found granted since: the next grant renews the store.
    private var sawNoAccess = false
    /// Number of reads whose result was applied, and of requests for one; tests wait on them.
    private(set) var appliedRefreshes = 0
    private(set) var refreshRequests = 0
    /// How many times the status was read again while waiting for the system to settle after a prompt; tests wait on it.
    private(set) var accessRechecks = 0
    /// What the notch activity shows now; nil while none is published.
    private(set) var publishedActivity: TodoActivityContent?

    private struct Want {
        var completed: Bool
        var serial: Int
    }

    public convenience init() {
        self.init(dataSource: TodoService())
    }

    /// Tests pass fakes: no EventKit, no real clock and no notification of the system.
    init(
        dataSource: any TodoDataSource,
        now: @escaping () -> Date = { .now },
        calendar: Calendar = .autoupdatingCurrent,
        dayChangeCenter: NotificationCenter = .default,
        wakeCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        activeCenter: NotificationCenter = .default,
        accessRecheck: (interval: Duration, limit: Duration) = TodoModule.defaultAccessRecheck,
        accessWatchInterval: Duration = .seconds(1)
    ) {
        self.dataSource = dataSource
        clock = now
        self.calendar = calendar
        self.dayChangeCenter = dayChangeCenter
        self.wakeCenter = wakeCenter
        self.activeCenter = activeCenter
        self.accessRecheck = accessRecheck
        self.accessWatchInterval = accessWatchInterval
        readAt = now()
        state = TodoState(now: readAt, calendar: calendar)
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        self.context = context
        usedSettings = TodoSettings(context.settings)
        context.hotkeys.register("openTodo", title: "Mở danh sách việc cần làm", initial: Self.openShortcut) { [weak self] in
            self?.openTab()
        }
        context.hotkeys.register("quickAddTodo", title: "Thêm việc nhanh", initial: Self.quickAddShortcut) { [weak self] in
            self?.openQuickAdd()
        }
        // Each source is asked for its stream here, not in the loop that reads it, so nothing that happens
        // from now on is missed while that loop is still getting started.
        refreshOn(dataSource.changes, debounced: false)
        refreshOn(Self.signals(named: .NSCalendarDayChanged, in: dayChangeCenter), debounced: true)
        refreshOn(Self.signals(named: NSWorkspace.didWakeNotification, in: wakeCenter), debounced: true)
        checkOn(Self.signals(named: NSApplication.didBecomeActiveNotification, in: activeCenter))
        let moduleSettings = context.settings
        context.run { [weak self] in
            for await _ in Observations({ TodoSettings(moduleSettings) }) { self?.settingsChanged() }
        }
        startRefresh()
    }

    public func stop() async {
        debounce?.cancel()
        debounce = nil
        lingerTimers.values.forEach { $0.cancel() }
        lingerTimers = [:]
        noticeTimer?.cancel()
        noticeTimer = nil
        focusTimer?.cancel()
        focusTimer = nil
        context = nil
        refreshGeneration += 1
        wanted = [:]
        read = []
        isAdding = false
        sawNoAccess = false
        publishedActivity = nil
        inFlightQuadrantMoves.removeAll()
        state.reset()
    }

    public func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id, title: "Việc cần làm", systemImage: "checklist", preferredHeight: TodoTabView.height,
            acceptsKeyboard: true, content: AnyView(TodoTabView(state: state, actions: actions))
        )
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        let dataSource = dataSource
        return AnyView(TodoSettingsView(
            settings: environment.settings,
            keys: TodoSettingsKeys(environment.settings),
            permissions: environment.permissions,
            loadLists: { await dataSource.lists() },
            accessAnswered: { [weak self] in self?.context?.run { await self?.noticeAnswer() } }
        ))
    }

    var actions: TodoActions {
        TodoActions(
            complete: { [weak self] id in self?.context?.run { await self?.complete(id) } },
            undo: { [weak self] id in self?.context?.run { await self?.undo(id) } },
            moveToQuadrant: { [weak self] id, quadrant in
                self?.context?.run { await self?.moveToQuadrant(id, quadrant) }
            },
            add: { [weak self] text in await self?.add(text) ?? false },
            requestAccess: { [weak self] in self?.context?.run { await self?.requestAccess() } },
            retry: { [weak self] in self?.startRefresh() },
            watchAccess: { [weak self] in await self?.watchAccess() },
            appeared: { [weak self] in self?.tabAppeared() }
        )
    }

    // MARK: Shortcuts

    /// ⌃⌥D.
    func openTab() {
        context?.presenter.open()
    }

    /// ⌃⌥⇧D: the tab opens, and its field takes the keyboard. Only this asks for it: a plain open never does.
    func openQuickAdd() {
        guard let context else { return }
        state.requestFocus()
        focusTimer?.cancel()
        focusTimer = context.scheduler.schedule(after: Self.focusRequestLifetime) { [weak self] in
            self?.focusTimer = nil
            self?.state.cancelFocusRequest()
        }
        context.presenter.open()
    }

    // MARK: Checking off

    /// Ticks the reminder off at once on the list, struck through with "Hoàn tác", then saves it in Reminders and reads
    /// again. A save that fails brings the row back and says so.
    func complete(_ id: String) async {
        guard let item = state.items.first(where: { $0.id == id }), !item.reminder.isCompleted else { return }
        let request = want(true, for: id)
        startLinger(id)
        rebuild()
        await save(completed: true, id: id, request: request)
    }

    /// "Hoàn tác": takes the tick back, and the row stays as it is.
    func undo(_ id: String) async {
        guard let item = state.items.first(where: { $0.id == id }), item.reminder.isCompleted else { return }
        let request = want(false, for: id)
        cancelLinger(id)
        rebuild()
        await save(completed: false, id: id, request: request)
    }

    private func want(_ completed: Bool, for id: String) -> Int {
        wantSerial += 1
        wanted[id] = Want(completed: completed, serial: wantSerial)
        return wantSerial
    }

    private func save(completed: Bool, id: String, request: Int) async {
        do {
            try await dataSource.setCompleted(completed, reminderID: id)
        } catch {
            // The title is the user's own text, so it is not logged.
            context?.logger.error("Could not save a reminder: \(String(describing: error), privacy: .public)")
            if wanted[id]?.serial == request {
                wanted[id] = nil
                // A tick that failed has nothing to undo; an undo that failed leaves the row ticked, with its undo to try again.
                if completed { cancelLinger(id) } else { startLinger(id) }
            }
            showNotice("Không cập nhật được việc này.")
            await refresh()
            return
        }
        // The read comes with the tick still laid over it, so the row does not blink back between the save and the read.
        await refresh()
        if wanted[id]?.serial == request { wanted[id] = nil }
    }

    private func startLinger(_ id: String) {
        guard let context else { return }
        state.lingering.insert(id)
        lingerTimers[id]?.cancel()
        lingerTimers[id] = context.scheduler.schedule(after: Self.lingerDuration) { [weak self] in
            self?.lingerTimers[id] = nil
            self?.state.lingering.remove(id)
        }
    }

    private func cancelLinger(_ id: String) {
        lingerTimers.removeValue(forKey: id)?.cancel()
        state.lingering.remove(id)
    }

    // MARK: Quadrant Move

    /// Moves a reminder to an Eisenhower quadrant by updating its priority / due date in Reminders and reading again.
    func moveToQuadrant(_ id: String, _ quadrant: EisenhowerQuadrant) async {
        guard let item = state.items.first(where: { $0.id == id }), !item.reminder.isCompleted else { return }
        let currentQuadrant = EisenhowerQuadrant.classify(item)
        guard currentQuadrant != quadrant else { return }
        guard inFlightQuadrantMoves.insert(id).inserted else { return }
        defer { inFlightQuadrantMoves.remove(id) }

        if item.reminder.isRecurring && (quadrant == .schedule || quadrant == .eliminate) {
            showNotice("Việc lặp lại phải có ngày hẹn.")
            return
        }

        do {
            try await dataSource.setQuadrant(quadrant, reminderID: id)
            await refresh()
            if !state.items.contains(where: { $0.id == id }) {
                showNotice("Đã chuyển sang \(quadrant.shortCode). Việc không còn hiện ở Hôm nay vì chưa có ngày.")
            } else {
                showNotice("Đã chuyển sang \(quadrant.shortCode).")
            }
        } catch {
            context?.logger.error("Could not move reminder to quadrant: \(String(describing: error), privacy: .public)")
            showNotice("Không chuyển được việc này.")
            await refresh()
        }
    }

    // MARK: Quick add

    /// Return: saves what the line says, then reads again so the reminder is on the list. A line with no title, or one
    /// arriving while another is being saved, does nothing; a failure keeps the line (the field only clears on `true`).
    @discardableResult
    func add(_ text: String) async -> Bool {
        guard let context, !isAdding, context.permissions.status(of: .reminders) == .granted,
              let draft = TodoQuickAddParser.parse(text, now: clock(), calendar: calendar), !draft.title.isEmpty
        else { return false }
        isAdding = true
        defer { isAdding = false }
        let chosen = context.settings.value(TodoSettingsKeys(context.settings).defaultListID)
        let new = NewTodo(title: draft.title, due: draft.due, priority: draft.priority, listID: chosen.isEmpty ? nil : chosen)
        do {
            try await dataSource.create(new)
        } catch {
            context.logger.error("Could not add a reminder: \(String(describing: error), privacy: .public)")
            showNotice("Không thêm được việc. Nhấn Return để thử lại.")
            return false
        }
        if let due = draft.due, let date = TodoReminder.dueDate(of: due, calendar: calendar), !calendar.isDate(date, inSameDayAs: clock()) {
            showNotice("Đã thêm cho ngày mai.")
        }
        await refresh()
        return true
    }

    private func showNotice(_ text: String) {
        guard let context else { return }
        state.notice = text
        noticeTimer?.cancel()
        noticeTimer = context.scheduler.schedule(after: Self.noticeDuration) { [weak self] in
            self?.noticeTimer = nil
            self?.state.notice = nil
        }
    }

    // MARK: Access

    /// The button of the hint: the one place the module asks, and only because the user clicked.
    public func requestAccess() async {
        guard let context else { return }
        let before = context.permissions.status(of: .reminders)
        let answer = await RemindersAccess(permissions: context.permissions).request(openSettingsIfDenied: true)
        context.logger.notice("\(TodoLog.request(before: before, after: answer), privacy: .public)")
        await noticeAnswer()
    }

    /// The prompt's answer is only believed once the system agrees: its status can lag the answer, and a refresh in that
    /// moment would show the hint to someone who has just said yes. So the status is read again, every 100 ms for up to 2 s,
    /// until it is no longer "not determined"; then the list is read.
    func noticeAnswer() async {
        guard let context else { return }
        var status = context.permissions.status(of: .reminders)
        var polls = 0
        let limit = max(Int(accessRecheck.limit / accessRecheck.interval), 1)
        while status == .notDetermined, polls < limit {
            do { try await Task.sleep(for: accessRecheck.interval) } catch { return }
            polls += 1
            accessRechecks += 1
            status = context.permissions.status(of: .reminders)
        }
        if polls > 0 { context.logger.notice("\(TodoLog.recheck(status: status, polls: polls), privacy: .public)") }
        await refresh()
    }

    /// Runs while the hint is on screen: access granted in System Settings (or by a prompt answered elsewhere) is noticed
    /// within a second, with no need for the tab to be opened again. Ends once the list shows, or when its task is cancelled.
    func watchAccess() async {
        while state.phase == .needsAccess {
            do { try await Task.sleep(for: accessWatchInterval) } catch { return }
            if needsRefresh() { await refresh() }
        }
    }

    /// Nothing tells the module when access changes in System Settings or a midnight passed while it was asleep, so it
    /// checks when the tab opens and when the app becomes active (coming back from System Settings). The clock the rows judge a
    /// time that has gone by is brought up to date too, with no read: it is the clock, not the reminders, that moved.
    func tabAppeared() {
        let now = clock()
        if state.phase != .loading, calendar.isDate(state.now, inSameDayAs: now), state.now < now { state.now = now }
        refreshIfStale()
    }

    private func refreshIfStale() {
        if needsRefresh() { startRefresh() }
    }

    /// Whether the list shows the wrong thing for the access there is now, or for the day it is now, or the last read failed.
    private func needsRefresh() -> Bool {
        guard let context, state.phase != .loading else { return false }
        let status = context.permissions.status(of: .reminders)
        let granted = status == .granted
        let accessChanged = (state.phase == .ready) != granted || (!granted && (status == .denied) != state.accessIsDenied)
        let newDay = !calendar.isDate(state.now, inSameDayAs: clock())
        return accessChanged || newDay || state.loadFailed
    }

    // MARK: Refreshing

    func refresh() async {
        guard let context else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let now = clock()
        let settings = TodoSettings(context.settings)
        usedSettings = settings
        let status = context.permissions.status(of: .reminders)
        context.logger.notice("\(TodoLog.refresh(status: status), privacy: .public)")
        guard status == .granted else {
            sawNoAccess = true
            state.accessIsDenied = status == .denied
            apply(read: [], rules: TodoRules(), now: now, phase: .needsAccess)
            return
        }
        state.accessIsDenied = false
        if sawNoAccess {
            // A store from before the grant can go on answering with nothing: start over with a new one.
            sawNoAccess = false
            await dataSource.accessWasGranted()
            context.logger.notice("\(TodoLog.storeRenewed, privacy: .public)")
        }
        let lists = await dataSource.lists()
        let defaultList = settings.includeUndated ? TodoListChoice.resolve(chosenID: settings.defaultListID, in: lists)?.id : nil
        let day = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: calendar.startOfDay(for: now), duration: 86_400)
        let incomplete: [TodoReminder]
        let completed: [TodoReminder]
        do {
            incomplete = try await dataSource.incomplete(dueBy: day.end, undatedIn: defaultList)
            completed = try await dataSource.completed(from: day.start, to: day.end)
        } catch {
            guard generation == refreshGeneration, self.context === context else { return }
            // Nothing read is not "nothing to do": the list stays as it was, with a line saying it could not be read.
            context.logger.error("Could not read reminders: \(String(describing: error), privacy: .public)")
            if state.phase == .loading { setPhase(.ready) }
            state.loadFailed = true
            appliedRefreshes += 1
            return
        }
        guard generation == refreshGeneration, self.context === context else { return }
        let rules = TodoRules(hiddenListIDs: Set(settings.hiddenListIDs), includeUndated: settings.includeUndated, defaultListID: defaultList)
        apply(read: incomplete + completed, rules: rules, now: now, phase: .ready)
        let line = TodoLog.read(lists: lists.count, incomplete: incomplete.count, completed: completed.count, items: state.items.count)
        context.logger.notice("\(line, privacy: .public)")
    }

    /// Phase changes are logged, so a tab stuck on the hint can be told from one that never read.
    private func setPhase(_ phase: TodoState.Phase) {
        guard state.phase != phase else { return }
        let line = TodoLog.phase(from: state.phase, to: phase)
        context?.logger.notice("\(line, privacy: .public)")
        state.phase = phase
    }

    private func apply(read: [TodoReminder], rules: TodoRules, now: Date, phase: TodoState.Phase) {
        self.read = read
        self.rules = rules
        readAt = now
        if state.loadFailed { state.loadFailed = false }
        setPhase(phase)
        if state.now != now { state.now = now }
        rebuild()
        appliedRefreshes += 1
    }

    /// The list from what was read and what the user has ticked since, then what the notch shows from it.
    private func rebuild() {
        let reminders = read.map { reminder in
            guard let want = wanted[reminder.id], want.completed != reminder.isCompleted else { return reminder }
            var ticked = reminder
            ticked.isCompleted = want.completed
            ticked.completionDate = want.completed ? readAt : nil
            return ticked
        }
        let items = TodoToday.items(from: reminders, rules: rules, now: readAt, calendar: calendar)
        if state.items != items { state.items = items }
        publishActivity()
    }

    /// Reads again, after a quiet second if the trigger can come in bursts.
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

    private func checkOn(_ stream: AsyncStream<Void>) {
        context?.run { [weak self] in
            for await _ in stream { self?.refreshIfStale() }
        }
    }

    private func settingsChanged() {
        guard let context else { return }
        let settings = TodoSettings(context.settings)
        guard settings != usedSettings else { return }
        if settings.readsSameReminders(as: usedSettings) {
            usedSettings = settings
            publishActivity()
        } else {
            startRefresh()
        }
    }

    /// The observer is added when the stream is made, and its token goes when the stream ends.
    private static func signals(named name: Notification.Name, in center: NotificationCenter) -> AsyncStream<Void> {
        let (stream, input) = AsyncStream<Void>.makeStream()
        let observer = ObserverToken(center.addObserver(forName: name, object: nil, queue: nil) { _ in input.yield() })
        input.onTermination = { _ in center.removeObserver(observer.token) }
        return stream
    }

    // MARK: Notch activity

    /// Sets the activity when its content changes and clears it when it hides, so it is only touched when the count moves.
    private func publishActivity() {
        guard let context else { return }
        var content: TodoActivityContent?
        if state.phase == .ready, context.settings.value(TodoSettingsKeys(context.settings).showRemaining) {
            let progress = state.progress
            if progress.remaining > 0 {
                content = TodoActivityContent(remaining: progress.remaining, done: progress.done, total: progress.total)
            }
        }
        guard content != publishedActivity else { return }
        publishedActivity = content
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

// MARK: - Todo Studio Integration

public struct TodoStudioItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let isCompleted: Bool
    public let quadrant: Int
    public let tags: [String]
    public let deadline: String?

    public init(id: String, title: String, isCompleted: Bool, quadrant: Int, tags: [String], deadline: String?) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.quadrant = quadrant
        self.tags = tags
        self.deadline = deadline
    }
}

extension TodoModule {
    public var studioTasks: [TodoStudioItem] {
        state.items.map { item in
            let q = EisenhowerQuadrant.classify(item)
            let timeStr = TodoFormat.time(of: item.reminder.due, calendar: Calendar.current)
            let deadlineStr: String?
            if let overdue = TodoFormat.overdueBadge(days: item.overdueDays) {
                deadlineStr = overdue
            } else {
                deadlineStr = timeStr
            }
            let tags = item.reminder.listTitle.isEmpty ? [] : [item.reminder.listTitle]
            return TodoStudioItem(
                id: item.id,
                title: item.reminder.title,
                isCompleted: item.reminder.isCompleted,
                quadrant: q.rawValue,
                tags: tags,
                deadline: deadlineStr
            )
        }
    }

    public func completeTask(_ id: String) async {
        await complete(id)
    }

    public func undoTask(_ id: String) async {
        await undo(id)
    }

    public func moveTask(_ id: String, toQuadrant q: Int) async {
        let target: EisenhowerQuadrant
        switch q {
        case 1: target = .doFirst
        case 2: target = .schedule
        case 3: target = .delegate
        case 4: target = .eliminate
        default: target = .doFirst
        }
        await moveToQuadrant(id, target)
    }

    public func addTask(_ text: String) async -> Bool {
        await add(text)
    }

    public func refreshTasks() async {
        await refresh()
    }

    public var hasRemindersAccess: Bool {
        context?.permissions.status(of: .reminders) == .granted
    }

    public func fetchArchivedTasks() async -> [TodoStudioItem] {
        guard let context, context.permissions.status(of: .reminders) == .granted else { return [] }
        let now = clock()
        let todayStart = calendar.startOfDay(for: now)
        let pastStart = calendar.date(byAdding: .day, value: -14, to: todayStart) ?? todayStart.addingTimeInterval(-14 * 86_400)
        do {
            let archivedReminders = try await dataSource.completed(from: pastStart, to: todayStart)
            return archivedReminders.map { reminder in
                let q = EisenhowerQuadrant.classify(
                    priority: reminder.priority,
                    hasDue: reminder.due != nil,
                    overdueDays: 0
                )
                let dateStr: String?
                if let compDate = reminder.completionDate {
                    let diff = calendar.dateComponents([.day], from: calendar.startOfDay(for: compDate), to: todayStart).day ?? 1
                    dateStr = diff == 1 ? "Hôm qua" : "\(diff) ngày trước"
                } else {
                    dateStr = "Đã lưu"
                }
                let tags = reminder.listTitle.isEmpty ? [] : [reminder.listTitle]
                return TodoStudioItem(
                    id: reminder.id,
                    title: reminder.title,
                    isCompleted: true,
                    quadrant: q.rawValue,
                    tags: tags,
                    deadline: dateStr
                )
            }
        } catch {
            return []
        }
    }
}
