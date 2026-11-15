import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

/// "Sửa" and "Chép" beside the capture just taken: when the chip comes and goes, and what its buttons reach.
extension ScreenshotModuleTests {
    @Test func aCaptureShowsTheChipWithItsThumbnailInsteadOfAnActivity() async throws {
        await start()

        await module.capture(mode: .regionOrWindow)

        #expect(chip.isVisible)
        #expect(chip.shown.count == 1)
        #expect(chip.current?.thumbnail != nil)
        #expect(activity == nil)
    }

    @Test func theChipIsOffWhenTheSettingIsOff() async throws {
        await start()
        let (settings, keys) = try settings()
        settings.set(false, for: keys.showCaptureChip)

        await module.capture(mode: .regionOrWindow)

        #expect(module.state.records.count == 1)
        #expect(chip.shown.isEmpty)
    }

    @Test func aCaptureThatCouldNotBeStoredShowsNoChip() async throws {
        await start()
        let storage = harness.storageRoot.storage(for: "screenshot")
        try FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
        try Data().write(to: storage.directory.appending(path: "captures"))

        await module.capture(mode: .regionOrWindow)

        #expect(module.state.records.isEmpty)
        #expect(chip.shown.isEmpty)
    }

    @Test func readingTextShowsNoChip() async {
        await start()

        await module.capture(mode: .ocrRegion)

        #expect(chip.shown.isEmpty)
    }

    // MARK: Time

    @Test func theChipGoesAfterSixSeconds() async {
        await start()
        await module.capture(mode: .regionOrWindow)

        harness.scheduler.advance(by: .milliseconds(5900))
        #expect(chip.isVisible)
        harness.scheduler.advance(by: .milliseconds(100))
        #expect(!chip.isVisible)
    }

    @Test func hoveringHoldsTheChipAndLeavingItHidesIt() async throws {
        await start()
        await module.capture(mode: .regionOrWindow)

        try #require(chip.current).hover(true)
        harness.scheduler.advance(by: .seconds(60))
        #expect(chip.isVisible)

        try #require(chip.current).hover(false)
        #expect(!chip.isVisible)
    }

    @Test func aNewCaptureTakesTheChipAwayBeforeTheScreensAreFrozen() async throws {
        await start()
        await module.capture(mode: .regionOrWindow)
        #expect(chip.isVisible)
        var visibleWhenFrozen: Bool?
        let chip = chip
        service.onFreeze = { visibleWhenFrozen = chip.isVisible }
        overlay.result = nil

        await module.capture(mode: .regionOrWindow)

        // The chip is a window of its own: if it were still up, the new capture would contain it.
        #expect(visibleWhenFrozen == false)
        #expect(!chip.isVisible)
        #expect(chip.shown.count == 1)
    }

    @Test func aNewCaptureGetsItsOwnChip() async throws {
        await start()
        await module.capture(mode: .regionOrWindow)
        harness.scheduler.advance(by: .seconds(5))

        await module.capture(mode: .regionOrWindow)

        #expect(chip.shown.count == 2)
        harness.scheduler.advance(by: .seconds(5))
        #expect(chip.isVisible)
        harness.scheduler.advance(by: .seconds(1))
        #expect(!chip.isVisible)
    }

    @Test func stoppingTheModuleTakesTheChipAway() async {
        await start()
        await module.capture(mode: .regionOrWindow)
        #expect(chip.isVisible)

        await harness.registry.setEnabled(false, for: "screenshot")

        #expect(!chip.isVisible)
    }

    // MARK: Buttons

    @Test(.timeLimit(.minutes(1))) func theEditButtonOpensTheEditorOnThatCapture() async throws {
        await start()
        await module.capture(mode: .regionOrWindow)
        let record = try #require(module.state.records.first)

        try #require(chip.current).edit()
        await waitUntil { editors.opened.count == 1 }

        #expect(editors.opened.map(\.record.id) == [record.id])
        let image = try #require(editors.opened.first?.source.image)
        #expect((image.width, image.height) == (40, 50))
        #expect(!chip.isVisible)
        // The notch makes way for the editor's window.
        #expect(harness.presenter.closeCount == 1)
    }

    @Test(.timeLimit(.minutes(1))) func theCopyButtonCopiesThatCaptureAndSaysSo() async throws {
        await start()
        await module.capture(mode: .regionOrWindow)
        let copies = pasteboard.images.count
        let toasts = harness.presenter.toastCount

        try #require(chip.current).copy()
        await waitUntil { pasteboard.images.count == copies + 1 }

        let copied = try #require(pasteboard.images.last)
        #expect((copied.image.width, copied.image.height) == (40, 50))
        #expect(!copied.markedAsOwn)
        await waitUntil { harness.presenter.toastCount == toasts + 1 }
        #expect(harness.presenter.toastCount == toasts + 1)
        #expect(!chip.isVisible)
    }

    @Test(.timeLimit(.minutes(1))) func thePinButtonPinsThatCapture() async throws {
        await start()
        await module.capture(mode: .regionOrWindow)

        try #require(chip.current).pin()
        await waitUntil { pinnedWindows.pinnedItems.count == 1 }

        #expect(pinnedWindows.pinnedItems.count == 1)
        #expect(!chip.isVisible)
    }

    @Test func nothingOpensUntilTheButtonIsPressed() async throws {
        await start()
        await module.capture(mode: .regionOrWindow)

        harness.scheduler.advance(by: .seconds(60))
        try? await Task.sleep(for: .milliseconds(50))

        #expect(editors.opened.isEmpty)
        #expect(module.editors == nil)
        #expect(harness.presenter.closeCount == 0)
    }

    @Test func stoppingClosesTheEditorsThatAreOpen() async throws {
        let record = try await capturedRecord()
        await module.edit(record)
        #expect(editors.opened.count == 1)

        await harness.registry.setEnabled(false, for: "screenshot")

        #expect(editors.closeAllCount == 1)
        #expect(module.editors == nil)
    }
}
