import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import ClipboardModule

/// Plays what AppKit did on a real machine when a pinned panel handed the keyboard back: the hidden panel took key status and left,
/// and the keyboard went straight back to the panel, because it was still a window that could become key (the unified log of that
/// run: `hand-back done back=false ... key=true`). It goes back to nobody only when the panel cannot become key. Nothing here moves key
/// status or shows a window.
final class FakePanelKeyboard {
    /// Whether the panel has the keyboard now.
    var panelIsKey = true
    /// nil plays the real machine; true or false forces the answer.
    var handBackWorks: Bool?
    /// What was asked, in order, with the state the panel was in at that moment.
    private(set) var calls: [String] = []

    var keyboard: ClipboardPanelKeyboard {
        ClipboardPanelKeyboard(
            frontApp: { nil },
            isKey: { [self] _ in panelIsKey },
            handBack: { [self] panel, _ in
                calls.append("hand back canBecomeKey=\(panel.canBecomeKey)")
                let back = handBackWorks ?? !panel.canBecomeKey
                if back { panelIsKey = false }
                return back
            },
            isWithFront: { [self] _ in
                calls.append("check")
                return !panelIsKey
            }
        )
    }
}

/// What the real panel and its controller do around the keyboard: a paste from a pinned panel can hand it back, which needs the panel
/// to be unable to take it again until the user comes back, and it comes back with a click or the hotkey.
@Suite final class ClipboardPanelKeyboardTests {
    /// Holds what the controller shows without keeping it, and counts how often it was ordered front (which also gives it the keyboard).
    final class Shown {
        weak var panel: ClipboardFloatingPanel?
        var orderedFront = 0
    }

    let fake = FakePanelKeyboard()
    let shown = Shown()
    let state = ClipboardState()
    let actions = FakePanelActions()

    func makeController() -> ClipboardPanelController {
        let shown = shown
        return ClipboardPanelController(
            interface: NotchInterface(), clickMonitor: ClipboardPanelClickMonitor(start: { _ in "token" }, stop: { _ in }),
            orderFront: { panel in
                shown.panel = panel
                shown.orderedFront += 1
            },
            keyboard: fake.keyboard
        )
    }

    func open(_ controller: ClipboardPanelController) -> ClipboardFloatingPanel? {
        let model = ClipboardPanelModel(state: state, actions: actions, isPinned: true)
        controller.show(AnyView(EmptyView()), model: model, restoringOrigin: nil, onClose: {})
        return shown.panel
    }

    func click(on panel: NSWindow) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: CGPoint(x: 5, y: 5), modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
    }

    // MARK: Handing the keyboard back

    @Test func thePanelCannotTakeTheKeyboardAgainWhileItHandsItToTheAppBehind() throws {
        let controller = makeController()
        let panel = try #require(open(controller))
        #expect(panel.canBecomeKey)

        let isBack = controller.returnKeyboard()

        // Before the hidden panel took the keyboard and left: otherwise AppKit gives it straight back to this one.
        #expect(fake.calls == ["hand back canBecomeKey=false"])
        #expect(isBack)
        #expect(!panel.canBecomeKey)
        #expect(controller.isOpen, "a pinned panel stays on screen")
    }

    @Test func aHandBackThatCouldNotMoveTheKeyboardLeavesThePanelAsItWas() throws {
        fake.handBackWorks = false
        let controller = makeController()
        let panel = try #require(open(controller))

        let isBack = controller.returnKeyboard()

        #expect(!isBack)
        // It has the keyboard still, and takes clicks and keys as before.
        #expect(panel.canBecomeKey)
        #expect(controller.isOpen)
    }

    @Test func aPanelThatHasNoKeyboardHasNothingToHandBackAndIsOnlyChecked() throws {
        fake.panelIsKey = false
        let controller = makeController()
        let panel = try #require(open(controller))

        let isBack = controller.returnKeyboard()

        #expect(isBack)
        #expect(fake.calls == ["check"])
        #expect(panel.canBecomeKey, "nothing was handed back, so nothing is locked")
    }

    @Test func withNoPanelOpenItIsOnlyAskedWhereTheKeyboardIs() {
        let controller = makeController()
        fake.panelIsKey = true
        #expect(!controller.returnKeyboard())
        #expect(controller.keyboardIsWithFrontApp() == false)
        fake.panelIsKey = false
        #expect(controller.keyboardIsWithFrontApp())
    }

    // MARK: Coming back to the panel

    @Test func theHotkeyGivesThePanelTheKeyboardAgain() throws {
        let controller = makeController()
        let panel = try #require(open(controller))
        #expect(controller.returnKeyboard())
        #expect(!panel.canBecomeKey)
        let before = shown.orderedFront

        controller.focus()

        // It can take the keyboard again before it is asked to, which is what ordering it front does.
        #expect(panel.canBecomeKey)
        #expect(shown.orderedFront == before + 1)
    }

    @Test func aClickOnThePanelGivesItTheKeyboardAgain() throws {
        let controller = makeController()
        let panel = try #require(open(controller))
        #expect(controller.returnKeyboard())
        #expect(!panel.canBecomeKey)

        panel.sendEvent(try click(on: panel))

        #expect(panel.canBecomeKey)
    }

    @Test func aKeyPressDoesNotTakeTheKeyboardBack() throws {
        let controller = makeController()
        let panel = try #require(open(controller))
        #expect(controller.returnKeyboard())

        let key = try #require(NSEvent.keyEvent(
            with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
            characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
        ))
        panel.sendEvent(key)

        #expect(!panel.canBecomeKey)
    }

    @Test func aSecondPasteAfterComingBackHandsTheKeyboardAwayAgain() throws {
        let controller = makeController()
        let panel = try #require(open(controller))
        #expect(controller.returnKeyboard())
        fake.panelIsKey = true
        panel.sendEvent(try click(on: panel))
        #expect(panel.canBecomeKey)

        #expect(controller.returnKeyboard())

        #expect(fake.calls == ["hand back canBecomeKey=false", "hand back canBecomeKey=false"])
        #expect(!panel.canBecomeKey)
    }
}

/// Return in a pinned panel pastes: the module, the panel's model and the real controller and panel together, with only AppKit's
/// answers played by a fake. The setup of the bug: the panel pinned, a row selected, Return pressed, the app behind taking ⌘V.
@Suite final class ClipboardPinnedPastePanelTests {
    let pasteboard = FakePasteboard()
    let keystrokes = FakeKeystrokeSender()
    let libraryWindow = FakeLibraryWindow()
    let system = FakeSystem()
    let modifiers = FakeModifierState()
    let fake = FakePanelKeyboard()
    let shown = ClipboardPanelKeyboardTests.Shown()
    let controller: ClipboardPanelController
    let module: ClipboardModule
    let harness: RegistryHarness
    let temporaryRoot: URL

    init() {
        let system = system
        let shown = shown
        controller = ClipboardPanelController(
            interface: NotchInterface(), clickMonitor: ClipboardPanelClickMonitor(start: { _ in "token" }, stop: { _ in }),
            orderFront: { shown.panel = $0 }, keyboard: fake.keyboard
        )
        module = ClipboardModule(
            pasteboard: pasteboard, keystrokes: keystrokes,
            frontmostApp: { system.frontmost }, isTrusted: { system.trusted },
            pasteboardAccessBehavior: { system.accessBehavior }, modifiers: modifiers, now: { system.now },
            libraryWindow: libraryWindow, panelWindow: controller
        )
        harness = RegistryHarness([module])
        temporaryRoot = harness.storageRoot.applicationSupport.deletingLastPathComponent()
    }

    deinit {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func start(pinned: Bool) async throws {
        let environment = try #require(harness.settingsEnvironment(for: "clipboard")).settings
        let keys = ClipboardSettingKeys(environment)
        environment.set(.paste, for: keys.clickAction)
        environment.set(pinned, for: keys.panelPinned)
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "clipboard") == .running)
    }

    func copy(_ text: String) {
        pasteboard.copy(PasteboardSnapshot(types: ["public.utf8-plain-text"], string: text))
        harness.scheduler.advance(by: ClipboardModuleTests.pollInterval)
    }

    @Test func returnInAPinnedPanelPastesAndTheSelectionAndThePanelStay() async throws {
        try await start(pinned: true)
        copy("Một")
        copy("Hai")
        module.togglePanel()
        let panel = try #require(module.panel)
        let first = try #require(panel.items.first { $0.content == .text("Một") })
        panel.chosenForTesting(first.id)

        // Return, as the key routing sends it.
        #expect(panel.handleKey(.activate))

        #expect(fake.calls == ["hand back canBecomeKey=false"])
        harness.scheduler.advance(by: .milliseconds(80))
        #expect(keystrokes.pasteCount == 1, "⌘V went out, because the keyboard was really handed back")
        #expect(pasteboard.writes.last?.content == .text("Một"))
        // The panel is still there, pinned, on the item that was pasted, and nothing says the paste failed.
        #expect(module.panel === panel)
        #expect(panel.isPinned)
        #expect(panel.selectedID == first.id)
        #expect(panel.notice == nil)
        #expect(!harness.activities.entries.contains { $0.id == "clipboard/pasteHint" })
        // And it cannot take the keyboard from the app that was pasted into, until the user comes back.
        #expect(!(try #require(shown.panel)).canBecomeKey)
    }

    @Test func whenTheKeyboardCannotBeHandedBackNothingIsPastedAndTheHintSaysSo() async throws {
        try await start(pinned: true)
        fake.handBackWorks = false
        copy("Một")
        module.togglePanel()
        let panel = try #require(module.panel)
        let item = try #require(panel.items.first)

        panel.activate(item.id)
        harness.scheduler.advance(by: .seconds(1))

        // R2a's rule: never ⌘V while a window of MyNotch has the keyboard.
        #expect(keystrokes.pasteCount == 0)
        #expect(pasteboard.writes.last?.content == .text("Một"))
        #expect(panel.notice?.text == "Đã chép — nhấn ⌘V để dán")
        #expect(harness.activities.entries.contains { $0.id == "clipboard/pasteHint" })
        #expect(module.panel === panel)
        #expect(try #require(shown.panel).canBecomeKey, "it has the keyboard, so it stays what it was")
    }

    @Test func theUnpinnedPanelStillClosesAndPastes() async throws {
        try await start(pinned: false)
        fake.panelIsKey = false
        copy("Một")
        module.togglePanel()
        let panel = try #require(module.panel)
        let item = try #require(panel.items.first)

        panel.activate(item.id)

        #expect(module.panel == nil)
        #expect(fake.calls == ["check"], "an unpinned panel leaves the screen; it is only checked")
        harness.scheduler.advance(by: .milliseconds(80))
        #expect(keystrokes.pasteCount == 1)
    }
}

extension ClipboardPanelModel {
    /// What the arrow keys or a click would have chosen.
    func chosenForTesting(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        for _ in 0..<index { _ = handleKey(.next) }
    }
}

/// The trace of the keyboard's hand-back. Its sink is one for the whole process, so the tests that read it run one at a time, and read
/// only what they are sure to have caused.
@Suite(.serialized) final class ClipboardPanelTraceTests {
    @Test func theHandBackAndTheComingBackAreLoggedWithoutAnyContent() throws {
        var lines: [String] = []
        ClipboardPanelLog.sink = { lines.append($0) }
        defer { ClipboardPanelLog.sink = nil }
        let tests = ClipboardPanelKeyboardTests()
        let controller = tests.makeController()
        let panel = try #require(tests.open(controller))

        _ = controller.returnKeyboard()
        panel.sendEvent(try tests.click(on: panel))
        controller.focus()

        #if DEBUG
        let text = lines.joined(separator: "\n")
        #expect(text.contains("hand-back begins"))
        #expect(text.contains("allowsKey=false"))
        #expect(text.contains("hand-back done back=true"))
        #expect(text.contains("allowsKey=true"))
        #expect(text.contains("focus requested"))
        #expect(lines.allSatisfy { $0.hasPrefix("t=") })
        #endif
    }

    @Test func aPinnedPasteLogsEachStepWithoutAnyContent() async throws {
        var lines: [String] = []
        ClipboardPanelLog.sink = { lines.append($0) }
        defer { ClipboardPanelLog.sink = nil }
        let tests = ClipboardPinnedPastePanelTests()
        try await tests.start(pinned: true)
        tests.copy("Một")
        tests.module.togglePanel()
        let panel = try #require(tests.module.panel)

        panel.activate(try #require(panel.items.first).id)
        tests.harness.scheduler.advance(by: .milliseconds(80))

        #if DEBUG
        let text = lines.joined(separator: "\n")
        #expect(text.contains("the keyboard goes back to the app behind, pinned=true"))
        #expect(text.contains("hand-back done back=true"))
        #expect(text.contains("panel paste: ⌘V is on its way"))
        #expect(text.contains("⌘V sent"))
        #expect(!text.contains("Một"), "no content in the trace")
        #endif
    }
}
