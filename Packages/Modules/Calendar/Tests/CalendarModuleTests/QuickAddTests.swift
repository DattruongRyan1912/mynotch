import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import CalendarModule

/// The "+" of the Calendar tab through the module: the line is read as it is typed, Return saves it to the chosen
/// calendar, Esc drops it. Saving goes to the data-source fake, never to a real calendar.
@Suite struct QuickAddTests {
    let calendar: Calendar
    let source = FakeCalendarDataSource()
    let clock: TestClock
    let module: CalendarModule
    let harness: RegistryHarness

    struct SaveFailure: Error {}

    /// Wednesday 14 October 2026, 09:00, in Ho Chi Minh City. The system puts new events in "Personal"; "Holidays" is read-only.
    init() {
        let calendar = fixedCalendar()
        let clock = TestClock(calendar.on(14, at: 9))
        self.calendar = calendar
        self.clock = clock
        module = CalendarModule(
            dataSource: source, now: { clock.now }, calendar: calendar, openURL: { _ in true },
            dayChangeCenter: NotificationCenter(), wakeCenter: NotificationCenter()
        )
        harness = RegistryHarness([module])
        harness.permissions.statuses[.calendars] = .granted
        source.calendars = [
            CalendarInfo(id: "work", title: "Work", color: .gray),
            CalendarInfo(id: "personal", title: "Personal", color: .gray, isDefaultForNewEvents: true),
            CalendarInfo(id: "holidays", title: "Holidays", color: .gray, allowsModifications: false),
        ]
    }

    var keys: CalendarSettingsKeys { CalendarSettingsKeys(harness.settingsEnvironment(for: "calendar")!.settings) }
    var quickAdd: QuickAddState? { module.state.quickAdd }

    func start() async {
        await harness.registry.bootstrap()
        await settle { module.appliedRefreshes >= 1 }
    }

    /// Opens the field and waits until it knows which calendar it saves to.
    func open() async {
        module.openQuickAdd()
        await settle { quickAdd?.calendar != nil || quickAdd?.canWrite == false }
    }

    func type(_ text: String) {
        module.editQuickAdd(text)
    }

    // MARK: Opening

    @Test func plusOpensAnEmptyFieldThatSavesToTheSystemsCalendar() async {
        await start()
        #expect(quickAdd == nil)
        await open()
        #expect(quickAdd?.text == "")
        #expect(quickAdd?.draft == nil)
        #expect(quickAdd?.canWrite == true)
        #expect(quickAdd?.phase == .editing)
        #expect(quickAdd?.calendar?.id == "personal")
    }

    @Test func openingAgainKeepsWhatWasTyped() async {
        await start()
        await open()
        type("Họp nhóm 3h chiều mai")
        module.openQuickAdd()
        #expect(quickAdd?.text == "Họp nhóm 3h chiều mai")
    }

    // MARK: Reading as it is typed

    @Test func theLineIsReadAsItIsTyped() async throws {
        await start()
        await open()
        type("Họp nhóm 3h chiều mai")
        let draft = try #require(quickAdd?.draft)
        #expect(draft.title == "Họp nhóm")
        #expect(draft.start == calendar.on(15, at: 15))
        #expect(draft.end == calendar.on(15, at: 16))
        #expect(!draft.isAllDay)
        type("Họp nhóm 3h chiều mai 2 tiếng")
        #expect(quickAdd?.draft?.end == calendar.on(15, at: 17))
        type("")
        #expect(quickAdd?.draft == nil)
        #expect(quickAdd?.text == "")
    }

    @Test func theDraftFollowsTheClockOfTheKeystroke() async throws {
        await start()
        await open()
        clock.now = calendar.on(14, at: 19)
        type("gym 18h")
        #expect(quickAdd?.draft?.start == calendar.on(15, at: 18))
    }

    // MARK: Saving

    @Test func returnSavesTheEventAndClosesTheField() async throws {
        await start()
        await open()
        type("Họp nhóm 3h chiều mai")

        await module.saveQuickAdd()

        #expect(source.createdEvents == [
            NewEvent(title: "Họp nhóm", start: calendar.on(15, at: 15), end: calendar.on(15, at: 16), isAllDay: false, calendarID: "personal", timeZone: calendar.timeZone),
        ])
        #expect(quickAdd == nil)
    }

    @Test func theSavedEventShowsUpWithoutWaitingForAChangeNotice() async {
        await start()
        await open()
        type("họp mai 9h")
        let applied = module.appliedRefreshes
        await module.saveQuickAdd()
        await settle { module.appliedRefreshes > applied }
        #expect(module.state.agenda.upcoming.map(\.title) == ["họp"])
    }

    @Test func aLineWithoutATimeIsAnAllDayEventTodayAndTheNoteSaysSo() async throws {
        await start()
        await open()
        type("Đi chợ")
        #expect(quickAdd?.draft?.note == .noTime)
        await module.saveQuickAdd()
        #expect(source.createdEvents == [
            NewEvent(title: "Đi chợ", start: calendar.on(14, at: 0), end: calendar.on(15, at: 0), isAllDay: true, calendarID: "personal", timeZone: calendar.timeZone),
        ])
    }

    @Test func aLineWithoutATitleOrWithoutTextSavesNothing() async {
        await start()
        await open()
        await module.saveQuickAdd()
        type("3h chiều mai")
        await module.saveQuickAdd()
        type("   ")
        await module.saveQuickAdd()
        #expect(source.createCalls == 0)
        #expect(quickAdd != nil)
    }

    @Test func escDropsTheLine() async {
        await start()
        await open()
        type("Họp nhóm 3h chiều mai")
        module.cancelQuickAdd()
        #expect(quickAdd == nil)
        await module.saveQuickAdd()
        #expect(source.createCalls == 0)
    }

    @Test func savingWithTheFieldClosedDoesNothing() async {
        await start()
        await module.saveQuickAdd()
        module.editQuickAdd("Họp 9h")
        #expect(quickAdd == nil)
        #expect(source.createCalls == 0)
    }

    @Test func theSecondReturnWhileSavingDoesNotSaveTwice() async {
        await start()
        await open()
        let gate = AsyncGate()
        source.createGate = { await gate.wait() }
        type("Họp nhóm 3h chiều mai")

        async let first: Void = module.saveQuickAdd()
        await settle { source.createCalls >= 1 }
        #expect(quickAdd?.phase == .saving)
        async let second: Void = module.saveQuickAdd()
        await letAnythingPending()
        gate.open()
        await first
        await second

        #expect(source.createCalls == 1)
        #expect(source.createdEvents.count == 1)
        #expect(quickAdd == nil)
    }

    @Test func aFailedSaveKeepsTheLineAndSaysSo() async {
        await start()
        await open()
        source.creationFailure = SaveFailure()
        type("Họp nhóm 3h chiều mai")

        await module.saveQuickAdd()

        #expect(quickAdd?.phase == .failed)
        #expect(quickAdd?.text == "Họp nhóm 3h chiều mai")
        #expect(source.createdEvents.isEmpty)

        // Return tries again, and editing clears the message.
        source.creationFailure = nil
        type("Họp nhóm 3h chiều mai 30m")
        #expect(quickAdd?.phase == .editing)
        await module.saveQuickAdd()
        #expect(source.createdEvents.count == 1)
        #expect(quickAdd == nil)
    }

    @Test func aLateAnswerDoesNotCloseAFieldThatWasClosedAndOpenedAgain() async {
        await start()
        await open()
        let gate = AsyncGate()
        source.createGate = { await gate.wait() }
        type("Họp nhóm 3h chiều mai")
        async let saving: Void = module.saveQuickAdd()
        await settle { source.createCalls >= 1 }

        module.cancelQuickAdd()
        await open()
        type("Đi chợ")
        gate.open()
        await saving

        #expect(quickAdd?.text == "Đi chợ")
        #expect(quickAdd?.phase == .editing)
    }

    @Test func aLateFailureDoesNotMarkAFieldThatWasClosedAndOpenedAgain() async {
        await start()
        await open()
        let gate = AsyncGate()
        source.createGate = { await gate.wait() }
        source.creationFailure = SaveFailure()
        type("Họp nhóm 3h chiều mai")
        async let saving: Void = module.saveQuickAdd()
        await settle { source.createCalls >= 1 }

        module.cancelQuickAdd()
        await open()
        type("Đi chợ")
        gate.open()
        await saving

        #expect(quickAdd?.text == "Đi chợ")
        #expect(quickAdd?.phase == .editing)
    }

    // MARK: Which calendar

    @Test func theSettingChoosesTheCalendar() async {
        harness.settings.set("work", for: keys.defaultCalendarID)
        await start()
        await open()
        #expect(quickAdd?.calendar?.title == "Work")
        type("họp mai 9h")
        await module.saveQuickAdd()
        #expect(source.createdEvents.first?.calendarID == "work")
    }

    @Test(arguments: ["holidays", "gone"])
    func aCalendarThatCannotTakeEventsOrNoLongerExistsFallsBackToTheSystemsOne(_ stale: String) async {
        harness.settings.set(stale, for: keys.defaultCalendarID)
        await start()
        await open()
        #expect(quickAdd?.calendar?.id == "personal")
    }

    @Test func withoutAListOfCalendarsTheSystemDecides() async {
        source.calendars = []
        await start()
        module.openQuickAdd()
        await letAnythingPending()
        #expect(quickAdd?.calendar == nil)
        type("họp mai 9h")
        await module.saveQuickAdd()
        #expect(source.createdEvents.first?.calendarID == nil)
    }

    // MARK: Without full access

    @Test func withoutFullAccessThereIsNothingToType() async {
        await start()
        source.setAuthorization(.denied, for: .calendars)
        await open()
        #expect(quickAdd?.canWrite == false)
        type("họp mai 9h")
        await module.saveQuickAdd()
        #expect(source.createCalls == 0)
        #expect(quickAdd?.draft == nil)
    }

    // MARK: Leaving

    @Test func theLineIsDroppedWhenTheTabLeavesTheScreen() async {
        await start()
        await open()
        type("Họp nhóm 3h chiều mai")
        module.tabDisappeared()
        #expect(quickAdd == nil)
        await module.saveQuickAdd()
        #expect(source.createCalls == 0)
        // Opened again it is a fresh field: nothing kept, so nothing stale to save.
        await open()
        #expect(quickAdd?.text == "")
        #expect(quickAdd?.draft == nil)
    }

    @Test func leavingWithNoFieldOpenDoesNothing() async {
        await start()
        module.tabDisappeared()
        #expect(quickAdd == nil)
    }

    @Test func aSaveInFlightWhenTheTabLeavesStillEndsUpOnTheList() async {
        await start()
        await open()
        let gate = AsyncGate()
        source.createGate = { await gate.wait() }
        type("họp mai 9h")
        async let saving: Void = module.saveQuickAdd()
        await settle { source.createCalls >= 1 }
        module.tabDisappeared()
        gate.open()
        await saving
        #expect(source.createdEvents.count == 1)
        #expect(quickAdd == nil)
    }

    @Test func theEventIsSavedInTheZoneItWasTypedIn() async {
        // A zone no machine running the tests is likely to be set to.
        let auckland = fixedCalendar("Pacific/Auckland")
        let source = FakeCalendarDataSource()
        source.calendars = self.source.calendars
        let module = CalendarModule(
            dataSource: source, now: { auckland.on(14, at: 9) }, calendar: auckland, openURL: { _ in true },
            dayChangeCenter: NotificationCenter(), wakeCenter: NotificationCenter()
        )
        let harness = RegistryHarness([module])
        harness.permissions.statuses[.calendars] = .granted
        await harness.registry.bootstrap()
        await settle { module.appliedRefreshes >= 1 }
        module.openQuickAdd()
        await settle { module.state.quickAdd?.calendar != nil }
        module.editQuickAdd("họp mai 9h")
        await module.saveQuickAdd()
        #expect(source.createdEvents.first?.timeZone == auckland.timeZone)
        #expect(source.createdEvents.first?.start == auckland.on(15, at: 9))
    }

    // MARK: Stopping

    @Test func stoppingTheModuleClosesTheField() async {
        await start()
        await open()
        type("Họp nhóm 3h chiều mai")
        await harness.registry.setEnabled(false, for: "calendar")
        #expect(quickAdd == nil)
    }
}

@Suite struct QuickAddTargetTests {
    let work = CalendarInfo(id: "work", title: "Work", color: .gray)
    let personal = CalendarInfo(id: "personal", title: "Personal", color: .gray, isDefaultForNewEvents: true)
    let holidays = CalendarInfo(id: "holidays", title: "Holidays", color: .gray, allowsModifications: false)
    var all: [CalendarInfo] { [holidays, work, personal] }

    @Test func theChosenCalendarWinsWhenItTakesEvents() {
        #expect(QuickAddTarget.resolve(chosenID: "work", in: all)?.id == "work")
    }

    @Test func otherwiseTheSystemsCalendarForNewEvents() {
        #expect(QuickAddTarget.resolve(chosenID: "", in: all)?.id == "personal")
        #expect(QuickAddTarget.resolve(chosenID: "holidays", in: all)?.id == "personal")
        #expect(QuickAddTarget.resolve(chosenID: "gone", in: all)?.id == "personal")
    }

    @Test func otherwiseTheFirstThatTakesEventsByTitle() {
        let calendars = [holidays, CalendarInfo(id: "z", title: "Zeta", color: .gray), CalendarInfo(id: "a", title: "Alpha", color: .gray)]
        #expect(QuickAddTarget.resolve(chosenID: "", in: calendars)?.id == "a")
    }

    @Test func noneWhenNothingTakesEventsOrNothingIsKnown() {
        #expect(QuickAddTarget.resolve(chosenID: "", in: [holidays]) == nil)
        #expect(QuickAddTarget.resolve(chosenID: "work", in: []) == nil)
    }
}
