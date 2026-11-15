import CoreGraphics
import MyNotchTestSupport
import Testing
@testable import ScreenshotModule

/// How long the chip beside a new capture stays, and what the pointer and its buttons do to it.
@Suite struct CaptureChipControllerTests {
    let scheduler = ManualScheduler()
    let presenter = FakeCaptureChip()
    let controller: CaptureChipController
    let edits = Counter()
    let copies = Counter()

    final class Counter {
        var count = 0
    }

    init() {
        controller = CaptureChipController(presenter: presenter, scheduler: scheduler)
    }

    func show() {
        let (edits, copies) = (self.edits, self.copies)
        controller.show(thumbnail: nil, edit: { edits.count += 1 }, copy: { copies.count += 1 })
    }

    @Test func showingPutsTheChipUpForSixSeconds() {
        #expect(CaptureChipController.lifetime == .seconds(6))
        show()
        #expect(presenter.isVisible)
        #expect(controller.isShown)

        scheduler.advance(by: .milliseconds(5999))
        #expect(presenter.isVisible)
        scheduler.advance(by: .milliseconds(1))
        #expect(!presenter.isVisible)
        #expect(!controller.isShown)
        #expect(presenter.hideCount == 1)
    }

    @Test func theChipCarriesTheThumbnail() throws {
        let image = try Bitmap.filled(width: 3, height: 3).image()
        controller.show(thumbnail: image, edit: {}, copy: {})
        #expect(presenter.current?.thumbnail === image)
    }

    @Test func hoveringHoldsTheChipPastItsTimeAndLeavingHidesItAtOnce() throws {
        show()
        scheduler.advance(by: .seconds(2))
        try #require(presenter.current).hover(true)

        scheduler.advance(by: .seconds(60))
        #expect(presenter.isVisible)

        try #require(presenter.current).hover(false)
        #expect(!presenter.isVisible)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func leavingWithoutHavingHoveredChangesNothing() throws {
        show()
        try #require(presenter.current).hover(false)
        #expect(presenter.isVisible)
        scheduler.advance(by: .seconds(6))
        #expect(!presenter.isVisible)
    }

    @Test func aNewChipStartsTheClockAgainAndForgetsAHover() throws {
        show()
        try #require(presenter.current).hover(true)
        show()
        #expect(presenter.shown.count == 2)

        scheduler.advance(by: .seconds(6))
        #expect(!presenter.isVisible)
    }

    @Test func theEarlierTimerDoesNotHideALaterChip() {
        show()
        scheduler.advance(by: .seconds(4))
        show()
        scheduler.advance(by: .seconds(4))
        #expect(presenter.isVisible)
        scheduler.advance(by: .seconds(2))
        #expect(!presenter.isVisible)
    }

    @Test func hidingCancelsTheTimerAndOnlyHidesWhatIsShown() {
        controller.hide()
        #expect(presenter.hideCount == 0)
        show()
        controller.hide()
        #expect(!presenter.isVisible)
        #expect(scheduler.pendingCount == 0)
        controller.hide()
        #expect(presenter.hideCount == 1)
    }

    @Test func theButtonsRunTheirActionAndTakeTheChipAway() throws {
        show()
        try #require(presenter.current).edit()
        #expect(edits.count == 1 && copies.count == 0)
        #expect(!presenter.isVisible)

        show()
        try #require(presenter.current).copy()
        #expect(edits.count == 1 && copies.count == 1)
        #expect(!presenter.isVisible)
    }

    @Test func nothingRunsUntilAButtonIsPressed() {
        show()
        scheduler.advance(by: .seconds(60))
        #expect(edits.count == 0 && copies.count == 0)
    }
}
