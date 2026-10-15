import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import TodoModule

@Suite struct TodoModuleTests {
    let f: ModuleFixture

    init() {
        f = ModuleFixture(ModuleFixture.aTypicalDay(fixedCalendar()))
    }

    // MARK: Module basics

    @Test func descriptor() {
        let descriptor = f.module.descriptor
        #expect(descriptor.id == "todo")
        #expect(descriptor.displayName == "Việc cần làm")
        #expect(descriptor.systemImage == "checklist")
        #expect(descriptor.defaultEnabled)
        #expect(descriptor.order == 650)
    }

    @Test func needsRemindersAccessAndSaysWhy() {
        let descriptor = f.module.descriptor
        #expect(descriptor.permissions == [.reminders])
        #expect(descriptor.optionalPermissions.isEmpty)
        #expect(descriptor.permissionReasons == [.reminders: "Đọc, thêm và đánh dấu xong các việc trong Lời nhắc."])
    }

    @Test func tab() async throws {
        await f.start()
        let tab = try #require(f.harness.registry.tabs.first)
        #expect(tab.id == "todo")
        #expect(tab.title == "Việc cần làm")
        #expect(tab.systemImage == "checklist")
        #expect(tab.preferredHeight == 220)
        // The field takes the keyboard once the notch is open on purpose.
        #expect(tab.acceptsKeyboard)
        #expect(f.harness.oversizedTabs.reports.isEmpty)
    }

    @Test func registersNoShortcutThatClashesWithAnotherDefault() async {
        await f.start()
        #expect(f.harness.defaultCollisions.reports.isEmpty)
        // The defaults of the app and the other modules, as they stand: ⌃⌥ with N, S, O, T, V, C, ⌃⌥⇧V, ⌃⌥⌘V and ⌘⇧C.
        let taken: [KeyboardShortcuts.Shortcut] = [
            .init(.n, modifiers: [.control, .option]), .init(.s, modifiers: [.control, .option]),
            .init(.o, modifiers: [.control, .option]), .init(.t, modifiers: [.control, .option]),
            .init(.v, modifiers: [.control, .option]), .init(.c, modifiers: [.control, .option]),
            .init(.v, modifiers: [.control, .option, .shift]), .init(.v, modifiers: [.control, .option, .command]),
            .init(.c, modifiers: [.command, .shift]),
        ]
        #expect(!taken.contains(TodoModule.openShortcut))
        #expect(!taken.contains(TodoModule.quickAddShortcut))
    }

    // MARK: Permission

    @Test func waitsForAccessWithoutAskingForIt() async {
        f.harness.permissions.statuses[.reminders] = .notDetermined
        await f.harness.registry.bootstrap()
        #expect(f.harness.registry.state(of: "todo") == .needsPermission(.reminders))
        #expect(f.harness.permissions.requested.isEmpty)
        #expect(f.source.fetchCount == 0)
        #expect(f.harness.registry.tabs.isEmpty)
    }

    @Test func startsOnceAccessIsGrantedInSystemSettings() async {
        f.harness.permissions.statuses[.reminders] = .notDetermined
        await f.harness.registry.bootstrap()

        f.harness.permissions.statuses[.reminders] = .granted
        await f.harness.registry.refreshPermissions()
        await settle { f.module.appliedRefreshes >= 1 }

        #expect(f.harness.registry.state(of: "todo") == .running)
        #expect(f.state.phase == .ready)
        #expect(f.harness.permissions.requested.isEmpty)
    }

    @Test func startingNeverPrompts() async {
        await f.start()
        #expect(f.harness.permissions.requested.isEmpty)
        #expect(f.harness.permissions.openedSettings.isEmpty)
    }

    @Test func accessTakenBackWhileRunningShowsTheHintWhenTheTabOpens() async {
        await f.start()
        #expect(f.state.phase == .ready)
        let fetches = f.source.fetchCount

        f.harness.permissions.statuses[.reminders] = .denied
        await f.refreshed { f.module.tabAppeared() }

        #expect(f.state.phase == .needsAccess)
        #expect(f.state.items.isEmpty)
        #expect(f.source.fetchCount == fetches)
        #expect(f.harness.permissions.requested.isEmpty)
    }

    @Test func theTabStaysAsItIsWhileAccessHoldsWhenItOpens() async {
        await f.start()
        let applied = f.module.appliedRefreshes
        f.module.tabAppeared()
        await letAnythingPending()
        #expect(f.module.appliedRefreshes == applied)
    }

    @Test func theButtonAsksOnlyWhenClickedAndTheListComesBackWithTheAnswer() async {
        await f.start()
        f.harness.permissions.statuses[.reminders] = .notDetermined
        await f.refreshed { f.module.tabAppeared() }
        #expect(f.state.phase == .needsAccess)
        #expect(f.harness.permissions.requested.isEmpty)

        await f.module.requestAccess()

        #expect(f.harness.permissions.requested == [.reminders])
        #expect(f.state.phase == .ready)
        #expect(!f.state.items.isEmpty)
    }

    @Test func aRefusedPromptKeepsTheHintAndSendsADeniedUserToSystemSettings() async {
        await f.start()
        f.harness.permissions.statuses[.reminders] = .denied
        f.harness.permissions.requestResult = .denied
        await f.refreshed { f.module.tabAppeared() }

        await f.module.requestAccess()

        #expect(f.state.phase == .needsAccess)
        #expect(f.harness.permissions.openedSettings == [.reminders])
    }

    @Test func theFirstRefusalDoesNotOpenSystemSettings() async {
        await f.start()
        f.harness.permissions.statuses[.reminders] = .notDetermined
        f.harness.permissions.requestResult = .denied
        await f.refreshed { f.module.tabAppeared() }

        await f.module.requestAccess()

        #expect(f.harness.permissions.openedSettings.isEmpty)
    }

    // MARK: The list

    @Test func startReadsTodaysListAndOrdersIt() async {
        await f.start()
        #expect(f.state.phase == .ready)
        // Overdue first, then today by time (10:00, 12:00), then a day alone (the urgent one first; the one done today keeps
        // its place), then no date. "later" and nothing of another day is there.
        #expect(f.itemIDs == ["overdue", "meeting", "lunch", "report", "shower", "idea"])
    }

    @Test func theCounterCountsWhatIsDoneAgainstWhatIsOnTheList() async {
        await f.start()
        #expect(f.state.progress == TodoProgress(done: 1, total: 6))
    }

    @Test func rowsLeaveOutWhatIsAlreadyDone() async {
        await f.start()
        #expect(!f.rowIDs.contains("shower"))
        #expect(f.rowIDs.count == 5)
    }

    @Test func overdueItemsCarryTheirDays() async throws {
        await f.start()
        #expect(try #require(f.state.items.first { $0.id == "overdue" }).overdueDays == 2)
    }

    @Test func readsFromTheDefaultListForUndatedAndAsksForOnlyThat() async {
        await f.start()
        #expect(f.source.undatedLists == ["inbox"])
    }

    // MARK: Settings

    @Test func hidingAListTakesItsItemsOffTheList() async {
        await f.start()
        #expect(f.itemIDs.contains("meeting"))
        await f.refreshed { f.settings.set(["work"], for: f.keys.hiddenListIDs) }
        #expect(!f.itemIDs.contains("meeting"))
        #expect(f.itemIDs.contains("lunch"))
    }

    @Test func switchingUndatedOffDropsThemAndAsksForNoneAfterwards() async {
        await f.start()
        await f.refreshed { f.settings.set(false, for: f.keys.includeUndated) }
        #expect(!f.itemIDs.contains("idea"))
        #expect(f.source.undatedLists.last == .some(nil))
    }

    @Test func aChosenDefaultListIsWhereUndatedItemsComeFrom() async {
        f.source.reminders += [todo("workIdea", list: "work")]
        await f.start()
        #expect(!f.itemIDs.contains("workIdea"))
        await f.refreshed { f.settings.set("work", for: f.keys.defaultListID) }
        #expect(f.itemIDs.contains("workIdea"))
        #expect(!f.itemIDs.contains("idea"))
        #expect(f.source.undatedLists.last == "work")
    }

    @Test func aDefaultListThatWasDeletedFallsBackToTheSystemsOne() async {
        f.settings.set("gone", for: f.keys.defaultListID)
        await f.start()
        #expect(f.itemIDs.contains("idea"))
        #expect(f.source.undatedLists == ["inbox"])
    }

    @Test func aSettingTheListDoesNotUseCausesNoRefresh() async {
        await f.start()
        let requests = f.module.appliedRefreshes
        f.settings.set(true, for: f.keys.showRemaining)
        f.settings.set(true, for: f.keys.showRemaining)
        await letAnythingPending()
        #expect(f.module.appliedRefreshes == requests)
    }

    @Test func settingsHaveTheirDefaults() {
        let keys = f.keys
        #expect(f.settings.value(keys.hiddenListIDs).isEmpty)
        #expect(f.settings.value(keys.includeUndated))
        #expect(f.settings.value(keys.defaultListID).isEmpty)
        #expect(!f.settings.value(keys.showRemaining))
    }

    // MARK: Sync

    @Test func aChangeFromAnotherDeviceShowsUpOnTheList() async {
        await f.start()
        #expect(!f.itemIDs.contains("call"))
        f.source.reminders += [todo("call", due: due(14, 15))]
        await f.refreshed { f.source.emitChange() }
        #expect(f.itemIDs.contains("call"))
    }

    @Test func eachSignalCostsOneRefresh() async {
        await f.start()
        let requests = f.module.refreshRequests
        await f.refreshed { f.source.emitChange() }
        #expect(f.module.refreshRequests == requests + 1)
    }

    @Test func aReminderCompletedElsewhereMovesToDone() async {
        await f.start()
        f.source.reminders = f.source.reminders.map {
            var reminder = $0
            if reminder.id == "report" { (reminder.isCompleted, reminder.completionDate) = (true, f.calendar.on(14, at: 9)) }
            return reminder
        }
        await f.refreshed { f.source.emitChange() }
        #expect(!f.rowIDs.contains("report"))
        #expect(f.state.progress == TodoProgress(done: 2, total: 6))
    }

    // MARK: Days change

    @Test func theNextDayCarriesWhatWasLeftOver() async throws {
        await f.start()
        #expect(try #require(f.state.items.first { $0.id == "report" }).overdueDays == 0)

        f.clock.now = f.calendar.on(15, at: 0, 1)
        f.source.now = f.clock.now
        await f.trigger { f.dayCenter.post(name: .NSCalendarDayChanged, object: nil) }
        await f.refreshed { f.harness.scheduler.advance(by: TodoModule.refreshDebounce) }

        let report = try #require(f.state.items.first { $0.id == "report" })
        #expect(report.overdueDays == 1)
        #expect(!f.itemIDs.contains("shower"))
        #expect(f.state.progress == TodoProgress(done: 0, total: 5))
        // Overdue ones lead, the oldest first; yesterday's day-long item before yesterday's timed ones; then what has no date.
        #expect(f.itemIDs == ["overdue", "report", "meeting", "lunch", "idea"])
    }

    @Test func aBurstOfDayChangesAndWakesIsOneRefresh() async {
        await f.start()
        let applied = f.module.appliedRefreshes
        await f.trigger { f.dayCenter.post(name: .NSCalendarDayChanged, object: nil) }
        await f.trigger { f.wakeCenter.post(name: NSWorkspace.didWakeNotification, object: nil) }
        await f.refreshed { f.harness.scheduler.advance(by: TodoModule.refreshDebounce) }
        await letAnythingPending()
        #expect(f.module.appliedRefreshes == applied + 1)
    }

    @Test func openingTheTabAfterAMissedMidnightReadsTheListAgain() async throws {
        await f.start()
        f.clock.now = f.calendar.on(15, at: 8)
        f.source.now = f.clock.now
        await f.refreshed { f.module.tabAppeared() }
        #expect(try #require(f.state.items.first { $0.id == "report" }).overdueDays == 1)
    }

    // MARK: Stopping

    @Test func stoppingClearsTheListAndTheShortcuts() async {
        await f.start()
        f.settings.set(true, for: f.keys.showRemaining)
        await settle { f.activityEntry != nil }
        await f.harness.registry.setEnabled(false, for: "todo")
        #expect(f.state.items.isEmpty)
        #expect(f.state.phase == .loading)
        #expect(f.activityEntry == nil)
        #expect(!f.harness.hotkeyBackend.trigger("todo_openTodo"))
    }
}
