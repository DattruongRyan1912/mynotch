import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import ClipboardModule

/// The copy stack as the module drives it, on the same fixture as `ClipboardModuleTests`.
extension ClipboardModuleTests {
    static let toggleStackID = "clipboard_toggleStack"
    static let pasteStackID = "clipboard_pasteStack"

    var stackTexts: [String] { state.stack.entries.compactMap { $0.item.content.plainText } }

    func activity(_ id: String) -> LiveActivity? {
        harness.activities.entries.first { $0.id == "clipboard/\(id)" }?.activity
    }

    /// The stack is turned on from its hotkey, the way the user does it.
    func startStack() {
        #expect(harness.hotkeyBackend.trigger(Self.toggleStackID))
        #expect(state.stack.isOn)
    }

    /// One press of the paste hotkey, then the 80 ms after which ⌘V goes out.
    func pasteNext() {
        #expect(harness.hotkeyBackend.trigger(Self.pasteStackID))
        harness.scheduler.advance(by: .milliseconds(80))
    }

    /// The next poll of the pasteboard, which is when the monitor would see what the module itself wrote.
    func poll() {
        harness.scheduler.advance(by: Self.pollInterval)
    }

    // MARK: Hotkeys

    @Test func theStackHasTwoHotkeysThatDoNotCollideWithTheModulesOthers() async throws {
        await start()

        let toggle = try #require(harness.hotkeys.registrations.first { $0.id == Self.toggleStackID })
        let paste = try #require(harness.hotkeys.registrations.first { $0.id == Self.pasteStackID })
        #expect(toggle.title == "Bật hoặc tắt ngăn xếp clipboard")
        #expect(paste.title == "Dán mục kế tiếp trong ngăn xếp")
        #expect(harness.hotkeyBackend.getShortcut(for: toggle.name) == KeyboardShortcuts.Shortcut(.c, modifiers: [.control, .option]))
        #expect(harness.hotkeyBackend.getShortcut(for: paste.name) == KeyboardShortcuts.Shortcut(.v, modifiers: [.control, .option, .command]))
        #expect(harness.hotkeys.registrations.count == 5)
        // Only this module's five: ⌃⌥V already opens the history, and two handlers on one key would both fire. The registry
        // reports a second registration with the same default to the harness's recorder (the app logs it instead), and sees
        // other modules' too wherever they run together, so a collision with one of them is the registry's to report.
        #expect(harness.defaultCollisions.reports.isEmpty)
        #expect(harness.hotkeys.conflicts().isEmpty)
    }

    @Test func theStackHotkeysGoWithTheModuleAndComeBackWithIt() async throws {
        await start()
        let toggle = try #require(harness.hotkeys.registrations.first { $0.id == Self.toggleStackID })
        // A combination the user chose in Settings is kept across the stop.
        let chosen = KeyboardShortcuts.Shortcut(.k, modifiers: [.control, .option])
        harness.hotkeyBackend.setShortcut(chosen, for: toggle.name)

        await harness.registry.setEnabled(false, for: "clipboard")
        #expect(!harness.hotkeyBackend.trigger(Self.toggleStackID))
        #expect(!harness.hotkeyBackend.trigger(Self.pasteStackID))
        #expect(harness.hotkeys.registrations.isEmpty)

        await harness.registry.setEnabled(true, for: "clipboard")
        let again = try #require(harness.hotkeys.registrations.first { $0.id == Self.toggleStackID })
        #expect(harness.hotkeyBackend.getShortcut(for: again.name) == chosen)
        #expect(harness.hotkeyBackend.trigger(Self.toggleStackID))
        #expect(state.stack.isOn)
        #expect(harness.hotkeyBackend.trigger(Self.pasteStackID))
    }

    @Test func theStackDoesNothingWhileTheModuleIsStopped() {
        module.toggleStack()
        module.pasteNextInStack()

        #expect(!state.stack.isOn)
        #expect(pasteboard.writes.isEmpty)
        #expect(harness.activities.entries.isEmpty)
    }

    // MARK: Turning it on and off

    @Test func theStackIsOffUntilTheUserStartsIt() async {
        await start()
        copy("trước khi bật")
        #expect(!state.stack.isOn)
        #expect(activity("stack") == nil)

        startStack()
        #expect(state.stack.entries.isEmpty)
    }

    @Test func aLiveActivityCountsTheItemsWhileTheStackIsOn() async {
        await start()
        startStack()
        #expect(activity("stack")?.summary == "Ngăn xếp: 0 mục")
        #expect(activity("stack")?.expiresAfter == nil)

        copy("một")
        copy("hai")
        #expect(activity("stack")?.summary == "Ngăn xếp: 2 mục")
        // One activity, updated in place, not one per copy.
        #expect(harness.activities.entries.filter { $0.id == "clipboard/stack" }.count == 1)
    }

    @Test func stoppingTheStackForgetsItsItemsAndSaysSoBriefly() async {
        await start()
        startStack()
        copy("một")

        #expect(harness.hotkeyBackend.trigger(Self.toggleStackID))

        #expect(!state.stack.isOn)
        #expect(state.stack.entries.isEmpty)
        #expect(activity("stack") == nil)
        #expect(activity("stackNotice")?.summary == "Đã tắt ngăn xếp")
        harness.scheduler.advance(by: .seconds(3))
        #expect(activity("stackNotice") == nil)
        // The history keeps what was copied.
        #expect(items.map(\.content) == [.text("một")])
    }

    // MARK: Collecting

    @Test func copiesAreCollectedInOrderAndAlsoStayInTheHistory() async {
        await start()
        startStack()
        copy("một")
        copy("hai")
        copy("ba")

        #expect(stackTexts == ["một", "hai", "ba"])
        #expect(items.map(\.content) == [.text("ba"), .text("hai"), .text("một")])
        #expect(state.stack.entries.map(\.item.id) == items.reversed().map(\.id))
    }

    @Test func nothingIsCollectedAfterTheStackIsStopped() async {
        await start()
        startStack()
        copy("một")
        module.stopStack()
        copy("hai")

        #expect(state.stack.entries.isEmpty)
        #expect(items.count == 2)
    }

    @Test func theSameTextCopiedTwiceIsStackedTwiceButKeptOnceInTheHistory() async {
        await start()
        startStack()
        copy("lặp")
        copy("xen kẽ")
        copy("lặp")

        #expect(stackTexts == ["lặp", "xen kẽ", "lặp"])
        #expect(items.count == 2)
    }

    @Test func anImageIsCollectedToo() async throws {
        await start()
        startStack()
        copy(PasteboardSnapshot(types: ["public.png"], png: ClipboardClassifierTests.png))

        guard case .image = try #require(state.stack.entries.first).item.content else {
            Issue.record("Expected an image on the stack")
            return
        }
    }

    @Test func whatMyNotchItselfWritesIsNotCollected() async throws {
        await start()
        startStack()
        copy("một")
        copy("hai")
        let first = try #require(state.stack.entries.first)

        // A paste from the history writes the pasteboard with MyNotch's marker; the next poll must skip it.
        module.copy(first.item)
        poll()

        #expect(stackTexts == ["một", "hai"])
        #expect(items.count == 2)
    }

    @Test func aConcealedCopyIsNeverCollectedWhateverTheHistoryDoes() async throws {
        let (settings, keys) = try settings()
        await start()
        startStack()
        let secret = PasteboardSnapshot(types: ["org.nspasteboard.ConcealedType", "public.utf8-plain-text"], string: "hunter2")

        // The default: the history skips it, so the stack never sees it.
        copy(secret)
        #expect(items.isEmpty)
        #expect(state.stack.entries.isEmpty)

        // With the history set to keep secrets, the stack still does not.
        settings.set(false, for: keys.ignoreSensitive)
        copy(secret)
        #expect(items.map(\.content) == [.text("hunter2")])
        #expect(state.stack.entries.isEmpty)

        copy("công khai")
        #expect(stackTexts == ["công khai"])
    }

    @Test func nothingIsCollectedWhileTheHistoryIsPaused() async throws {
        let (settings, keys) = try settings()
        await start()
        startStack()
        settings.set(true, for: keys.paused)
        copy("tạm dừng")

        #expect(state.stack.entries.isEmpty)
    }

    // MARK: Pasting one after another

    @Test func eachPressPastesTheNextItemFirstInFirstOut() async {
        await start()
        startStack()
        copy("một")
        copy("hai")
        copy("ba")

        pasteNext()
        #expect(pasteboard.writes.map(\.content) == [.text("một")])
        #expect(keystrokes.pasteCount == 1)
        #expect(stackTexts == ["hai", "ba"])
        #expect(activity("stack")?.summary == "Ngăn xếp: 2 mục")

        pasteNext()
        pasteNext()
        #expect(pasteboard.writes.map(\.content) == [.text("một"), .text("hai"), .text("ba")])
        #expect(keystrokes.pasteCount == 3)
        #expect(state.stack.entries.isEmpty)
        #expect(activity("stack")?.summary == "Ngăn xếp: 0 mục")
    }

    @Test func theSettingCanPasteTheNewestFirst() async throws {
        let (settings, keys) = try settings()
        settings.set(.lastIn, for: keys.stackOrder)
        await start()
        startStack()
        copy("một")
        copy("hai")
        copy("ba")

        pasteNext()
        pasteNext()
        pasteNext()

        #expect(pasteboard.writes.map(\.content) == [.text("ba"), .text("hai"), .text("một")])
        #expect(keystrokes.pasteCount == 3)
    }

    @Test func theStackSettingsStartWithFirstInFirstOutAndNothingKept() throws {
        let (settings, keys) = try settings()
        #expect([keys.stackOrder.name, keys.stackPersist.name] == ["module.clipboard.stackOrder", "module.clipboard.stackPersist"])
        #expect(settings.value(keys.stackOrder) == .firstIn)
        #expect(settings.value(keys.stackPersist) == false)
    }

    @Test func pastingFromTheStackLeavesTheHistoryOrderAlone() async {
        await start()
        startStack()
        copy("một")
        copy("hai")
        copy("ba")
        let before = items.map(\.id)

        pasteNext()
        pasteNext()

        #expect(items.map(\.id) == before)
    }

    @Test func pastingFromTheStackDoesNotCollectItsOwnWrite() async {
        await start()
        startStack()
        copy("một")
        copy("hai")

        pasteNext()
        poll()

        #expect(stackTexts == ["hai"])
    }

    @Test func theStackPastesEvenWhenTheClickActionIsCopy() async throws {
        let (settings, keys) = try settings()
        settings.set(.copy, for: keys.clickAction)
        await start()
        startStack()
        copy("một")

        pasteNext()

        #expect(keystrokes.pasteCount == 1)
    }

    @Test func theKeyboardIsCheckedAfterTheWriteAndBeforeCommandVIsScheduled() async {
        await start()
        startStack()
        copy("một")
        let pendingBefore = harness.scheduler.pendingCount
        var seen: (writes: Int, pending: Int)?
        panelWindow.onKeyboardCheck = { [self] in seen = (pasteboard.writes.count, harness.scheduler.pendingCount) }

        #expect(harness.hotkeyBackend.trigger(Self.pasteStackID))

        #expect(panelWindow.keyboardCheckCount == 1)
        #expect(seen?.writes == 1)
        #expect(seen?.pending == pendingBefore)
        #expect(harness.scheduler.pendingCount == pendingBefore + 1)
        harness.scheduler.advance(by: .milliseconds(80))
        #expect(keystrokes.pasteCount == 1)
    }

    @Test func anOpenPinnedPanelHandsTheKeyboardBackAndStaysOpen() async throws {
        let (settings, keys) = try settings()
        settings.set(true, for: keys.panelPinned)
        await start()
        startStack()
        copy("một")
        module.togglePanel()

        pasteNext()

        #expect(panelWindow.keyboardReturnCount == 1)
        #expect(panelWindow.isOpen)
        #expect(keystrokes.pasteCount == 1)
        #expect(state.stack.entries.isEmpty)
    }

    // MARK: Waiting for the hotkey's keys

    /// The shortcut fires when V goes up, while ⌃⌥⌘ are normally still down: ⌘V must not be posted until they are up, and the
    /// item must leave the stack only when ⌘V really went out.
    @Test func theItemLeavesTheStackOnlyWhenCommandVIsSent() async {
        await start()
        startStack()
        copy("một")

        #expect(harness.hotkeyBackend.trigger(Self.pasteStackID))
        #expect(keystrokes.pasteCount == 0)
        #expect(stackTexts == ["một"])

        harness.scheduler.advance(by: .milliseconds(80))
        #expect(keystrokes.pasteCount == 1)
        #expect(stackTexts.isEmpty)
    }

    @Test func commandVWaitsForTheKeysToBeLetGoAndGoesOutOnceAfterwards() async {
        await start()
        startStack()
        copy("một")
        copy("hai")
        modifiers.held = true

        #expect(harness.hotkeyBackend.trigger(Self.pasteStackID))
        harness.scheduler.schedule(after: .milliseconds(200)) { [modifiers] in modifiers.held = false }

        harness.scheduler.advance(by: .milliseconds(199))
        #expect(keystrokes.pasteCount == 0)
        #expect(stackTexts == ["một", "hai"])
        #expect(activity("pasteHint") == nil)

        harness.scheduler.advance(by: .milliseconds(16))
        #expect(keystrokes.pasteCount == 1)
        #expect(stackTexts == ["hai"])
        harness.scheduler.advance(by: .seconds(2))
        #expect(keystrokes.pasteCount == 1)
        #expect(pasteboard.writes.map(\.content) == [.text("một")])
    }

    @Test func keysThatStayDownForASecondMeanCopyOnlyAndTheItemStaysOnTheStack() async {
        await start()
        startStack()
        copy("một")
        modifiers.held = true

        #expect(harness.hotkeyBackend.trigger(Self.pasteStackID))
        harness.scheduler.advance(by: .milliseconds(80) + .milliseconds(990))
        #expect(activity("pasteHint") == nil)
        harness.scheduler.advance(by: .milliseconds(30))

        #expect(keystrokes.pasteCount == 0)
        #expect(stackTexts == ["một"])
        #expect(pasteboard.writes.map(\.content) == [.text("một")])
        // The usual message: the item is on the pasteboard for the user's own ⌘V.
        #expect(activity("pasteHint") != nil)

        modifiers.held = false
        pasteNext()
        #expect(keystrokes.pasteCount == 1)
        #expect(stackTexts.isEmpty)
    }

    @Test func stoppingTheModuleWhileWaitingSendsNothing() async {
        await start()
        startStack()
        copy("một")
        modifiers.held = true
        #expect(harness.hotkeyBackend.trigger(Self.pasteStackID))
        harness.scheduler.advance(by: .milliseconds(100))

        await harness.registry.setEnabled(false, for: "clipboard")
        modifiers.held = false
        harness.scheduler.advance(by: .seconds(3))

        #expect(keystrokes.pasteCount == 0)
    }

    /// The second press takes over from the first, which never sent anything: nothing lost, nothing doubled.
    @Test func aSecondPressWhileWaitingNeitherLosesNorDoublesAnItem() async {
        await start()
        startStack()
        copy("một")
        copy("hai")
        modifiers.held = true

        #expect(harness.hotkeyBackend.trigger(Self.pasteStackID))
        harness.scheduler.advance(by: .milliseconds(100))
        #expect(harness.hotkeyBackend.trigger(Self.pasteStackID))
        modifiers.held = false
        harness.scheduler.advance(by: .seconds(1))

        #expect(keystrokes.pasteCount == 1)
        #expect(pasteboard.writes.map(\.content) == [.text("một"), .text("một")])
        #expect(stackTexts == ["hai"])
    }

    // MARK: When the paste cannot be done

    /// A window of MyNotch has the keyboard, so ⌘V would land in it: copy only, and the same item is next again.
    @Test func ifTheKeyboardIsNotWithTheAppInFrontItOnlyCopiesAndDoesNotAdvance() async {
        await start()
        startStack()
        copy("một")
        copy("hai")
        panelWindow.frontAppHasKeyboardAfterClose = false

        pasteNext()

        #expect(pasteboard.writes.map(\.content) == [.text("một")])
        #expect(keystrokes.pasteCount == 0)
        #expect(stackTexts == ["một", "hai"])
        // The hint beside the notch says the item is on the pasteboard for ⌘V.
        #expect(activity("pasteHint") != nil)

        panelWindow.frontAppHasKeyboardAfterClose = true
        pasteNext()
        #expect(pasteboard.writes.map(\.content) == [.text("một"), .text("một")])
        #expect(keystrokes.pasteCount == 1)
        #expect(stackTexts == ["hai"])
    }

    @Test func aPinnedPanelThatCannotGiveTheKeyboardBackOnlyCopiesAndDoesNotAdvance() async throws {
        let (settings, keys) = try settings()
        settings.set(true, for: keys.panelPinned)
        await start()
        startStack()
        copy("một")
        module.togglePanel()
        panelWindow.handBackWorks = false

        pasteNext()

        #expect(pasteboard.writes.map(\.content) == [.text("một")])
        #expect(keystrokes.pasteCount == 0)
        #expect(stackTexts == ["một"])
        #expect(activity("pasteHint") != nil)
    }

    @Test func withoutAccessibilityItOnlyCopiesAndDoesNotAdvance() async {
        system.trusted = false
        await start()
        startStack()
        copy("một")

        pasteNext()

        #expect(pasteboard.writes.map(\.content) == [.text("một")])
        #expect(keystrokes.pasteCount == 0)
        #expect(stackTexts == ["một"])
        #expect(activity("pasteHint") != nil)
    }

    @Test func aWriteThatFailsDoesNotAdvance() async {
        await start()
        startStack()
        copy("một")
        pasteboard.writesSucceed = false

        pasteNext()

        #expect(keystrokes.pasteCount == 0)
        #expect(stackTexts == ["một"])
        #expect(harness.presenter.toastCount == 1)
    }

    // MARK: Empty and off

    @Test func pastingFromAnEmptyStackTurnsItOffAndSaysSoBriefly() async {
        await start()
        startStack()

        pasteNext()

        #expect(!state.stack.isOn)
        #expect(activity("stack") == nil)
        #expect(activity("stackNotice")?.summary == "Ngăn xếp đã hết")
        #expect(pasteboard.writes.isEmpty)
        #expect(keystrokes.pasteCount == 0)
        harness.scheduler.advance(by: .seconds(3))
        #expect(activity("stackNotice") == nil)
    }

    /// After the last item the stack waits for more copies; the next press finds it empty and ends it.
    @Test func theNextPressAfterTheLastItemTurnsTheStackOff() async {
        await start()
        startStack()
        copy("một")

        pasteNext()
        #expect(state.stack.isOn)
        #expect(activity("stack")?.summary == "Ngăn xếp: 0 mục")

        pasteNext()
        #expect(!state.stack.isOn)
        #expect(activity("stackNotice")?.summary == "Ngăn xếp đã hết")
        #expect(keystrokes.pasteCount == 1)
    }

    @Test func pastingWithTheStackOffPastesNothingAndSaysItIsOff() async {
        await start()
        copy("một")

        pasteNext()

        #expect(pasteboard.writes.isEmpty)
        #expect(keystrokes.pasteCount == 0)
        #expect(activity("stackNotice")?.summary == "Ngăn xếp đang tắt")
    }

    // MARK: An image that is gone

    /// Deleting the history item deletes the image file while the stack still lists it.
    func deleteImageFile(of entry: CopyStackEntry) throws {
        guard case .image(let image) = entry.item.content else { return }
        try FileManager.default.removeItem(at: imageFile(image.fileName))
    }

    @Test func anImageWhoseFileIsGoneIsDroppedWithANoteAndTheNextItemIsPasted() async throws {
        await start()
        startStack()
        copy(PasteboardSnapshot(types: ["public.png"], png: ClipboardClassifierTests.png))
        copy("còn")
        try deleteImageFile(of: try #require(state.stack.entries.first))

        pasteNext()

        #expect(pasteboard.writes.map(\.content) == [.text("còn")])
        #expect(keystrokes.pasteCount == 1)
        #expect(stackTexts.isEmpty)
        #expect(activity("stackNotice")?.summary == "Đã bỏ 1 mục không còn trên đĩa")
        #expect(harness.presenter.toastCount == 0)
    }

    @Test func aStackLeftWithOnlyGoneImagesEndsInsteadOfGettingStuck() async throws {
        let (settings, keys) = try settings()
        settings.set(.lastIn, for: keys.stackOrder)
        await start()
        startStack()
        copy(PasteboardSnapshot(types: ["public.png"], png: ClipboardClassifierTests.png))
        try deleteImageFile(of: try #require(state.stack.entries.first))

        pasteNext()

        #expect(pasteboard.writes.isEmpty)
        #expect(keystrokes.pasteCount == 0)
        #expect(!state.stack.isOn)
        #expect(activity("stackNotice")?.summary == "Ngăn xếp đã hết")
    }

    // MARK: In the bubble beside the notch

    @Test func theCountAlsoHasAPlaceInTheBubbleThatShowsWhenAnotherActivityTakesTheNotch() async {
        await start()
        startStack()
        #expect(activity("stack")?.minimal != nil)
        #expect(activity("stack")?.summary == "Ngăn xếp: 0 mục")
    }

    // MARK: Editing

    @Test func entriesCanBeRemovedMovedAndCleared() async throws {
        await start()
        startStack()
        copy("một")
        copy("hai")
        copy("ba")

        module.moveInStack(from: IndexSet(integer: 2), to: 0)
        #expect(stackTexts == ["ba", "một", "hai"])

        module.removeFromStack(try #require(state.stack.entries.first { $0.item.content.plainText == "một" }).id)
        #expect(stackTexts == ["ba", "hai"])
        #expect(activity("stack")?.summary == "Ngăn xếp: 2 mục")

        // The order the user made is the order it pastes in.
        pasteNext()
        #expect(pasteboard.writes.map(\.content) == [.text("ba")])

        module.clearStack()
        #expect(state.stack.isOn)
        #expect(state.stack.entries.isEmpty)
        #expect(activity("stack")?.summary == "Ngăn xếp: 0 mục")
        // History is untouched by editing the stack.
        #expect(items.count == 3)
    }

    // MARK: Keeping the stack across a restart

    func stackFileIsGone() async -> Bool {
        await module.store?.waitForWrites()
        return !exists(directory.appending(path: "stack.json"))
    }

    func savedStack() -> CopyStack? {
        makeStore().loadStack()
    }

    @Test func byDefaultTheStackIsNotKeptAcrossARestart() async throws {
        let (settings, keys) = try settings()
        #expect(settings.value(keys.stackPersist) == false)
        await start()
        startStack()
        copy("bí mật")
        #expect(await stackFileIsGone())

        await harness.registry.setEnabled(false, for: "clipboard")
        await harness.registry.setEnabled(true, for: "clipboard")

        #expect(!state.stack.isOn)
        #expect(state.stack.entries.isEmpty)
        #expect(activity("stack") == nil)
        #expect(!exists(directory.appending(path: "stack.json")))
    }

    @Test func aStackFileLeftFromBeforeIsDeletedWhenTheSettingIsOff() async {
        let store = makeStore()
        _ = store.load()
        var old = CopyStack()
        old.start()
        old.collect(Self.item(.text("cũ"), copiedAt: system.now))
        store.saveStack(old)
        await store.waitForWrites()
        #expect(exists(directory.appending(path: "stack.json")))

        await start()

        #expect(await stackFileIsGone())
        #expect(state.stack.entries.isEmpty)
    }

    @Test func withTheSettingOnTheStackComesBackAfterARestartAndKeepsCounting() async throws {
        let (settings, keys) = try settings()
        settings.set(true, for: keys.stackPersist)
        await start()
        startStack()
        copy("một")
        copy("hai")
        let before = state.stack

        await harness.registry.setEnabled(false, for: "clipboard")
        #expect(state.stack.entries.isEmpty)
        await harness.registry.setEnabled(true, for: "clipboard")

        #expect(state.stack == before)
        #expect(activity("stack")?.summary == "Ngăn xếp: 2 mục")
        pasteNext()
        #expect(pasteboard.writes.map(\.content) == [.text("một")])
    }

    @Test func theFileFollowsEveryChangeToAKeptStack() async throws {
        let (settings, keys) = try settings()
        settings.set(true, for: keys.stackPersist)
        await start()
        startStack()
        copy("một")
        copy("hai")
        copy("ba")
        await module.store?.waitForWrites()
        #expect(savedStack() == state.stack)

        pasteNext()
        await module.store?.waitForWrites()
        #expect(savedStack() == state.stack)
        #expect(savedStack()?.entries.count == 2)

        module.moveInStack(from: IndexSet(integer: 1), to: 0)
        await module.store?.waitForWrites()
        #expect(savedStack() == state.stack)

        module.clearStack()
        await module.store?.waitForWrites()
        #expect(savedStack() == state.stack)
        #expect(savedStack()?.entries.isEmpty == true)
    }

    @Test func stoppingAKeptStackRemovesItsFile() async throws {
        let (settings, keys) = try settings()
        settings.set(true, for: keys.stackPersist)
        await start()
        startStack()
        copy("một")
        await module.store?.waitForWrites()
        #expect(exists(directory.appending(path: "stack.json")))

        module.stopStack()

        #expect(await stackFileIsGone())
    }

    @Test func turningTheSettingOffRemovesTheFileAndOnWritesTheStackAtOnce() async throws {
        let (settings, keys) = try settings()
        await start()
        startStack()
        copy("một")
        #expect(await stackFileIsGone())

        settings.set(true, for: keys.stackPersist)
        for _ in 0..<1000 where savedStack() == nil {
            await module.store?.waitForWrites()
            await Task.yield()
        }
        #expect(savedStack() == state.stack)

        settings.set(false, for: keys.stackPersist)
        for _ in 0..<1000 where exists(directory.appending(path: "stack.json")) {
            await module.store?.waitForWrites()
            await Task.yield()
        }
        #expect(await stackFileIsGone())
        // Turning it off only stops keeping it; the stack in use carries on.
        #expect(stackTexts == ["một"])
    }

    @Test func aRestoredStackDropsImagesWhoseFileIsGone() async throws {
        let (settings, keys) = try settings()
        settings.set(true, for: keys.stackPersist)
        let kept = Self.item(.text("còn"), copiedAt: system.now)
        let lost = Self.item(Self.image("mất"), copiedAt: system.now)
        var saved = CopyStack()
        saved.start()
        saved.collect(lost)
        saved.collect(kept)
        let store = makeStore()
        _ = store.load()
        store.saveStack(saved)
        await store.waitForWrites()

        await start()

        #expect(stackTexts == ["còn"])
        #expect(activity("stack")?.summary == "Ngăn xếp: 1 mục")
    }
}
