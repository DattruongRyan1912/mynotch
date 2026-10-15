import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import TodoModule

/// What the tab's buttons and the shortcuts do: tick off and undo, quick add, open.
@Suite struct TodoModuleActionTests {
    let f: ModuleFixture

    init() {
        f = ModuleFixture(ModuleFixture.aTypicalDay(fixedCalendar()))
    }

    var lingerDuration: Duration { TodoModule.lingerDuration }

    // MARK: Checking off

    @Test func tickingOffCompletesTheReminderInTheStore() async {
        await f.start()
        await f.module.complete("report")
        #expect(f.source.completionCalls.map(\.id) == ["report"])
        #expect(f.source.completionCalls.map(\.completed) == [true])
        #expect(f.source.reminders.first { $0.id == "report" }?.isCompleted == true)
    }

    @Test func theRowStaysStruckThroughWithUndoThenGoesAfterTwoSeconds() async throws {
        await f.start()
        await f.module.complete("report")

        let row = try #require(f.state.rows.first { $0.id == "report" })
        #expect(row.reminder.isCompleted)
        #expect(f.state.lingering == ["report"])

        f.harness.scheduler.advance(by: lingerDuration - .milliseconds(1))
        #expect(f.rowIDs.contains("report"))
        f.harness.scheduler.advance(by: .milliseconds(1))
        #expect(!f.rowIDs.contains("report"))
        #expect(f.state.lingering.isEmpty)
        // It is done, not gone: it still counts.
        #expect(f.state.progress == TodoProgress(done: 2, total: 6))
    }

    @Test func theLingerIsTwoSeconds() {
        #expect(TodoModule.lingerDuration == .seconds(2))
    }

    @Test func theRowIsStruckThroughAtOnceNotAfterTheSave() async throws {
        await f.start()
        let gate = AsyncGate()
        f.source.completionGate = { await gate.wait() }

        let saving = Task { await f.module.complete("report") }
        await settle { gate.waitCalls == 1 }

        // EventKit has not answered yet, and the row already shows it done.
        #expect(try #require(f.state.rows.first { $0.id == "report" }).reminder.isCompleted)
        #expect(f.state.progress.done == 2)

        gate.open()
        await saving.value
        #expect(try #require(f.state.rows.first { $0.id == "report" }).reminder.isCompleted)
    }

    @Test func aRefreshBeforeTheSaveFinishesDoesNotBringTheRowBack() async throws {
        await f.start()
        let gate = AsyncGate()
        f.source.completionGate = { await gate.wait() }
        let saving = Task { await f.module.complete("report") }
        await settle { gate.waitCalls == 1 }

        await f.refreshed { f.source.emitChange() }

        #expect(try #require(f.state.rows.first { $0.id == "report" }).reminder.isCompleted)
        gate.open()
        await saving.value
    }

    @Test func undoTakesTheTickBackAndKeepsTheRow() async throws {
        await f.start()
        await f.module.complete("report")
        await f.module.undo("report")

        #expect(f.source.completionCalls.map(\.completed) == [true, false])
        #expect(f.source.reminders.first { $0.id == "report" }?.isCompleted == false)
        let row = try #require(f.state.rows.first { $0.id == "report" })
        #expect(!row.reminder.isCompleted)
        #expect(f.state.lingering.isEmpty)
        #expect(f.state.progress == TodoProgress(done: 1, total: 6))
    }

    @Test func anUndoneRowDoesNotDisappearWhenTheTimerWouldHaveFired() async {
        await f.start()
        await f.module.complete("report")
        await f.module.undo("report")
        f.harness.scheduler.advance(by: lingerDuration * 2)
        #expect(f.rowIDs.contains("report"))
        #expect(f.harness.scheduler.pendingCount == 0)
    }

    @Test func aFailedSaveBringsTheRowBackAndSaysSo() async throws {
        await f.start()
        f.source.completionFailure = TodoServiceError.reminderNotFound

        await f.module.complete("report")

        let row = try #require(f.state.rows.first { $0.id == "report" })
        #expect(!row.reminder.isCompleted)
        #expect(f.state.lingering.isEmpty)
        #expect(f.state.progress == TodoProgress(done: 1, total: 6))
        #expect(f.state.notice == "Không cập nhật được việc này.")
    }

    @Test func tickingTwoRowsKeepsBothUntilEachTimerFires() async {
        await f.start()
        await f.module.complete("report")
        f.harness.scheduler.advance(by: .seconds(1))
        await f.module.complete("lunch")
        #expect(f.state.lingering == ["report", "lunch"])

        f.harness.scheduler.advance(by: .seconds(1))
        #expect(f.state.lingering == ["lunch"])
        f.harness.scheduler.advance(by: .seconds(1))
        #expect(f.state.lingering.isEmpty)
    }

    @Test func tickingAReminderThatIsNotThereChangesNothing() async {
        await f.start()
        let before = f.state.items
        await f.module.complete("nothing")
        #expect(f.source.completionCalls.isEmpty)
        #expect(f.state.items == before)
    }

    @Test func tickingTheSameRowTwiceSavesOnce() async {
        await f.start()
        await f.module.complete("report")
        await f.module.complete("report")
        #expect(f.source.completionCalls.count == 1)
    }

    @Test func theButtonsOfTheTabDoTheSame() async {
        await f.start()
        f.module.actions.complete("report")
        await settle { f.source.completionCalls.count == 1 }
        await settle { f.state.progress.done == 2 && f.state.lingering == ["report"] }
        f.module.actions.undo("report")
        await settle { f.source.completionCalls.count == 2 }
        await settle { f.state.progress.done == 1 }
        #expect(f.source.completionCalls.map(\.completed) == [true, false])
    }

    // MARK: Quick add

    @Test func returnCreatesAReminderDueTodayInTheDefaultList() async throws {
        await f.start()
        #expect(await f.module.add("mua sữa"))
        let created = try #require(f.source.created.first)
        #expect(created.title == "mua sữa")
        #expect(created.due.day == 14)
        #expect(created.due.hour == nil)
        #expect(created.priority == .none)
        #expect(created.listID == nil)
        #expect(f.itemIDs.contains("created1"))
    }

    @Test func theLineIsReadForTimeAndPriority() async throws {
        await f.start()
        #expect(await f.module.add("!!! gọi khách 15h30"))
        let created = try #require(f.source.created.first)
        #expect(created.title == "gọi khách")
        #expect(created.due.hour == 15)
        #expect(created.due.minute == 30)
        #expect(created.priority == .high)
    }

    @Test func aChosenListIsWhereTheReminderGoes() async throws {
        await f.start()
        f.settings.set("work", for: f.keys.defaultListID)
        await settle { f.module.appliedRefreshes >= 2 }
        #expect(await f.module.add("báo cáo"))
        #expect(try #require(f.source.created.first).listID == "work")
        #expect(f.source.reminders.first { $0.id == "created1" }?.listID == "work")
    }

    @Test func aReminderForTomorrowIsAddedButLeftOffTodaysListWithANoteSayingSo() async throws {
        await f.start()
        #expect(await f.module.add("mua sữa mai 9h"))
        #expect(try #require(f.source.created.first).due.day == 15)
        #expect(!f.itemIDs.contains("created1"))
        #expect(f.state.notice == "Đã thêm cho ngày mai.")
    }

    @Test func theNoteGoesAfterThreeSeconds() async {
        await f.start()
        await f.module.add("mua sữa mai")
        #expect(f.state.notice != nil)
        f.harness.scheduler.advance(by: TodoModule.noticeDuration)
        #expect(f.state.notice == nil)
        #expect(TodoModule.noticeDuration == .seconds(3))
    }

    @Test func aLineWithNoTitleCreatesNothing() async {
        await f.start()
        #expect(!(await f.module.add("")))
        #expect(!(await f.module.add("   ")))
        #expect(!(await f.module.add("!!!")))
        #expect(f.source.createCalls == 0)
    }

    @Test func aFailedSaveKeepsTheLineAndSaysSo() async {
        await f.start()
        f.source.creationFailure = TodoServiceError.noWritableList
        #expect(!(await f.module.add("mua sữa")))
        #expect(f.state.notice == "Không thêm được việc. Nhấn Return để thử lại.")
        #expect(f.source.created.isEmpty)

        f.source.creationFailure = nil
        #expect(await f.module.add("mua sữa"))
        #expect(f.source.created.count == 1)
    }

    @Test func aSecondReturnWhileSavingDoesNothing() async {
        await f.start()
        let gate = AsyncGate()
        f.source.createGate = { await gate.wait() }
        let first = Task { await f.module.add("mua sữa") }
        await settle { gate.waitCalls == 1 }

        #expect(!(await f.module.add("mua sữa")))
        gate.open()
        #expect(await first.value)
        #expect(f.source.createCalls == 1)
    }

    @Test func addingWithoutAccessSavesNothingAndKeepsTheLine() async {
        await f.start()
        f.harness.permissions.statuses[.reminders] = .denied
        #expect(!(await f.module.add("mua sữa")))
        #expect(f.source.createCalls == 0)
    }

    @Test func theFieldOfTheTabAddsToo() async {
        await f.start()
        #expect(await f.module.actions.add("mua sữa"))
        #expect(f.source.created.count == 1)
    }

    // MARK: Shortcuts

    @Test func registersTheTwoShortcutsWithTheirDefaults() async throws {
        await f.start()
        let registrations = f.harness.hotkeys.registrations
        let open = try #require(registrations.first { $0.id == "todo_openTodo" })
        let quick = try #require(registrations.first { $0.id == "todo_quickAddTodo" })
        #expect(open.title == "Mở danh sách việc cần làm")
        #expect(quick.title == "Thêm việc nhanh")
        #expect(f.harness.hotkeyBackend.getShortcut(for: open.name) == KeyboardShortcuts.Shortcut(.d, modifiers: [.control, .option]))
        #expect(f.harness.hotkeyBackend.getShortcut(for: quick.name) == KeyboardShortcuts.Shortcut(.d, modifiers: [.control, .option, .shift]))
        #expect(open.owner == "todo" && quick.owner == "todo")
    }

    @Test func theFirstShortcutOpensTheTab() async {
        await f.start()
        #expect(f.harness.hotkeyBackend.trigger("todo_openTodo"))
        #expect(f.harness.presenter.openedTabs == ["todo"])
        #expect(f.state.focusRequest == 0)
    }

    @Test func theSecondOpensTheTabAndAsksForTheFieldToBeFocused() async {
        await f.start()
        #expect(f.harness.hotkeyBackend.trigger("todo_quickAddTodo"))
        #expect(f.harness.presenter.openedTabs == ["todo"])
        #expect(f.state.focusRequest == 1)
        #expect(f.harness.hotkeyBackend.trigger("todo_quickAddTodo"))
        #expect(f.state.focusRequest == 2)
    }

    @Test func aShortcutTheUserRebindKeepsItsHandler() async throws {
        await f.start()
        let open = try #require(f.harness.hotkeys.registrations.first { $0.id == "todo_openTodo" })
        f.harness.hotkeyBackend.setShortcut(KeyboardShortcuts.Shortcut(.k, modifiers: [.control, .option]), for: open.name)
        #expect(f.harness.hotkeyBackend.trigger("todo_openTodo"))
        #expect(f.harness.presenter.openedTabs == ["todo"])
        #expect(f.harness.hotkeys.conflicts().isEmpty)
    }

    @Test func theShortcutsGoWhenTheModuleStops() async {
        await f.start()
        await f.harness.registry.setEnabled(false, for: "todo")
        #expect(f.harness.hotkeys.registrations.isEmpty)
        #expect(!f.harness.hotkeyBackend.trigger("todo_quickAddTodo"))
    }
}
