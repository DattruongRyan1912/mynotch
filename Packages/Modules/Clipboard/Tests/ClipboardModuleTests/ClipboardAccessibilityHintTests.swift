import Foundation
import MyNotchCore
import Testing
@testable import ClipboardModule

/// The hint that clicking a card pastes but Accessibility has not been allowed, on the same fixture as `ClipboardModuleTests`.
extension ClipboardModuleTests {
    @Test func aClickPastesByDefault() async throws {
        let (settings, keys) = try settings()
        #expect(settings.value(keys.clickAction) == .paste)
        system.trusted = true
        await start()
        copy("Xin chào")

        module.activate(try #require(items.first))
        harness.scheduler.advance(by: .milliseconds(80))

        #expect(keystrokes.pasteCount == 1)
    }

    @Test func aChoiceOfCopyIsKept() async throws {
        let (settings, keys) = try settings()
        settings.set(.copy, for: keys.clickAction)
        #expect(settings.value(keys.clickAction) == .copy)
        await start()
        copy("Xin chào")

        module.activate(try #require(items.first))
        harness.scheduler.advance(by: .seconds(1))

        #expect(keystrokes.pasteCount == 0)
    }

    @Test func theHintShowsWhenAClickPastesWithoutAccessibility() async {
        system.trusted = false
        await start()
        #expect(state.needsAccessibility)
    }

    @Test func noHintOnceAccessibilityIsGrantedAndItGoesByItselfOnTheNextCheck() async {
        system.trusted = false
        await start()
        #expect(state.needsAccessibility)

        system.trusted = true
        // The views check when they appear and every 2 seconds while they are shown.
        #expect(state.needsAccessibility)
        module.refreshAccessibility()
        #expect(!state.needsAccessibility)

        system.trusted = false
        module.refreshAccessibility()
        #expect(state.needsAccessibility)
    }

    @Test func noHintWhenTheClickActionIsCopy() async throws {
        let (settings, keys) = try settings()
        settings.set(.copy, for: keys.clickAction)
        system.trusted = false
        await start()
        #expect(!state.needsAccessibility)

        settings.set(.paste, for: keys.clickAction)
        module.refreshAccessibility()
        #expect(state.needsAccessibility)

        settings.set(.copy, for: keys.clickAction)
        module.refreshAccessibility()
        #expect(!state.needsAccessibility)
    }

    @Test func noHintWhileStopped() async {
        system.trusted = false
        module.refreshAccessibility()
        #expect(!state.needsAccessibility)

        await start()
        #expect(state.needsAccessibility)
        await harness.registry.setEnabled(false, for: "clipboard")
        #expect(!state.needsAccessibility)
    }

    @Test func theGrantButtonPromptsAndThenOpensTheAccessibilityPane() async {
        system.trusted = false
        harness.permissions.requestResult = .denied
        await start()

        await module.requestAccessibility()?.value

        #expect(harness.permissions.requested == [.accessibility])
        #expect(harness.permissions.openedSettings == [.accessibility])
        #expect(state.needsAccessibility)
    }

    @Test func theGrantButtonLeavesSettingsClosedWhenTheSystemAlreadyTrustsTheApp() async {
        system.trusted = false
        await start()
        // Allowed in the prompt's own dialog: trust is there when the request returns.
        system.trusted = true
        harness.permissions.requestResult = .granted

        await module.requestAccessibility()?.value

        #expect(harness.permissions.requested == [.accessibility])
        #expect(harness.permissions.openedSettings.isEmpty)
        #expect(!state.needsAccessibility)
    }

    @Test func theGrantButtonDoesNothingWhileStopped() async {
        #expect(module.requestAccessibility() == nil)
        #expect(harness.permissions.requested.isEmpty)
    }
}
