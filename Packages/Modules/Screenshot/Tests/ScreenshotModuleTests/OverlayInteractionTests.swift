import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct OverlayInteractionTests {
    /// MacBook display at the origin (scale 2) and a 4K monitor (scale 1) above it, as in the geometry tests.
    let primary = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)
    let external = DisplayInfo(id: 2, frame: CGRect(x: -1164, y: 982, width: 3840, height: 2160), scale: 1)
    let ownPID: pid_t = 100

    /// Front to back, CG global points: a menu bar item, MyNotch's own panel, then two ordinary windows.
    var windows: [CapturableWindow] {
        [
            CapturableWindow(id: 10, ownerPID: 7, layer: 25, bounds: CGRect(x: 0, y: 0, width: 1512, height: 30)),
            CapturableWindow(id: 11, ownerPID: ownPID, layer: 0, bounds: CGRect(x: 600, y: 100, width: 300, height: 300)),
            CapturableWindow(id: 12, ownerPID: 7, layer: 0, bounds: CGRect(x: 100, y: 100, width: 400, height: 300)),
            CapturableWindow(id: 13, ownerPID: 8, layer: 0, bounds: CGRect(x: 80, y: 80, width: 800, height: 600)),
        ]
    }

    func start(_ mode: SelectionMode = .regionOrWindow) -> OverlayInteraction {
        OverlayInteraction(mode: mode, displays: [primary, external], windows: windows, excludingPID: ownPID)
    }

    /// Drags from `start` to `end` and releases there.
    func drag(_ interaction: inout OverlayInteraction, from start: CGPoint, to end: CGPoint) -> OverlayInteraction.Outcome {
        _ = interaction.mouseDown(at: start)
        interaction.mouseDragged(to: end)
        return interaction.mouseUp(at: end)
    }

    // MARK: Keys

    @Test func mapsKeyCodes() {
        #expect(OverlayInteraction.key(forKeyCode: 53) == .escape)
        #expect(OverlayInteraction.key(forKeyCode: 49) == .space)
        #expect(OverlayInteraction.key(forKeyCode: 36) == .returnKey)
        #expect(OverlayInteraction.key(forKeyCode: 76) == .returnKey)
        #expect(OverlayInteraction.key(forKeyCode: 0) == nil)
    }

    @Test(arguments: [SelectionMode.region, .regionOrWindow, .ocrRegion])
    func escapeCancelsInEveryMode(mode: SelectionMode) {
        var interaction = start(mode)
        #expect(interaction.keyDown(.escape, pointer: CGPoint(x: 100, y: 100)) == .cancel)
    }

    @Test func escapeCancelsWhileDragging() {
        var interaction = start()
        _ = interaction.mouseDown(at: CGPoint(x: 100, y: 100))
        interaction.mouseDragged(to: CGPoint(x: 300, y: 300))
        #expect(interaction.keyDown(.escape, pointer: CGPoint(x: 300, y: 300)) == .cancel)
    }

    @Test func returnCapturesTheDisplayUnderThePointer() {
        var interaction = start()
        #expect(interaction.keyDown(.returnKey, pointer: CGPoint(x: 100, y: 100)) == .finish(.fullScreen(displayID: 1)))
        #expect(interaction.keyDown(.returnKey, pointer: CGPoint(x: -1000, y: 2000)) == .finish(.fullScreen(displayID: 2)))
    }

    @Test func returnWithThePointerOutsideEveryDisplayTakesTheFirst() {
        var interaction = start()
        #expect(interaction.keyDown(.returnKey, pointer: CGPoint(x: -5000, y: -5000)) == .finish(.fullScreen(displayID: 1)))
    }

    @Test func returnWorksInWindowModeAndWhileDragging() {
        var interaction = start()
        _ = interaction.keyDown(.space, pointer: CGPoint(x: 200, y: 200))
        #expect(interaction.keyDown(.returnKey, pointer: CGPoint(x: 200, y: 200)) == .finish(.fullScreen(displayID: 1)))
        var dragging = start(.region)
        _ = dragging.mouseDown(at: CGPoint(x: 10, y: 10))
        #expect(dragging.keyDown(.returnKey, pointer: CGPoint(x: 10, y: 10)) == .finish(.fullScreen(displayID: 1)))
    }

    @Test func withoutDisplaysEverythingCancelsOrIsIgnored() {
        var interaction = OverlayInteraction(mode: .regionOrWindow, displays: [], windows: [], excludingPID: ownPID)
        #expect(interaction.keyDown(.returnKey, pointer: .zero) == .cancel)
        #expect(interaction.mouseDown(at: .zero) == .none)
    }

    // MARK: Region drags

    @Test func dragSelectsARegionInImagePixels() {
        var interaction = start()
        _ = interaction.mouseDown(at: CGPoint(x: 100, y: 100))
        #expect(interaction.highlight == .none)
        interaction.mouseDragged(to: CGPoint(x: 200, y: 150))
        #expect(interaction.highlight == .region(displayID: 1, rect: CGRect(x: 100, y: 100, width: 100, height: 50), pixelSize: CGSize(width: 200, height: 100)))
        // Image rows count from the display's top: (982 − 150) × 2.
        #expect(interaction.mouseUp(at: CGPoint(x: 200, y: 150)) == .finish(.region(displayID: 1, pixelRect: CGRect(x: 200, y: 1664, width: 200, height: 100))))
    }

    @Test func dragInAnyDirectionSelectsTheSameRegion() {
        let expected = OverlayInteraction.Outcome.finish(.region(displayID: 1, pixelRect: CGRect(x: 200, y: 1664, width: 200, height: 100)))
        for (from, to) in [
            (CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 150)), (CGPoint(x: 200, y: 150), CGPoint(x: 100, y: 100)),
            (CGPoint(x: 200, y: 100), CGPoint(x: 100, y: 150)), (CGPoint(x: 100, y: 150), CGPoint(x: 200, y: 100)),
        ] {
            var interaction = start()
            #expect(drag(&interaction, from: from, to: to) == expected)
        }
    }

    @Test func selectionIsSnappedToPixelsAndDrawsTheCroppedRect() {
        var interaction = start()
        _ = interaction.mouseDown(at: CGPoint(x: 100.2, y: 100.3))
        interaction.mouseDragged(to: CGPoint(x: 200.6, y: 150.1))
        // x 200.4 → 200 px and 401.2 → 401 px; y from the top 1663.8 → 1664 and 1763.4 → 1763.
        #expect(interaction.highlight == .region(displayID: 1, rect: CGRect(x: 100, y: 100.5, width: 100.5, height: 49.5), pixelSize: CGSize(width: 201, height: 99)))
        #expect(interaction.mouseUp(at: CGPoint(x: 200.6, y: 150.1)) == .finish(.region(displayID: 1, pixelRect: CGRect(x: 200, y: 1664, width: 201, height: 99))))
    }

    @Test func dragEndingOnAnotherDisplayIsClampedToTheStartDisplay() {
        var interaction = start()
        _ = interaction.mouseDown(at: CGPoint(x: 1400, y: 500))
        interaction.mouseDragged(to: CGPoint(x: -500, y: 1500))
        #expect(interaction.highlight == .region(displayID: 1, rect: CGRect(x: 0, y: 500, width: 1400, height: 482), pixelSize: CGSize(width: 2800, height: 964)))
        #expect(interaction.mouseUp(at: CGPoint(x: -500, y: 1500)) == .finish(.region(displayID: 1, pixelRect: CGRect(x: 0, y: 0, width: 2800, height: 964))))
    }

    @Test func dragOnTheExternalDisplayUsesItsOriginAndScale() {
        var interaction = start()
        // x from the display's left (−1164): 164…364; y from its top (3142): 1142…1342.
        #expect(drag(&interaction, from: CGPoint(x: -1000, y: 2000), to: CGPoint(x: -800, y: 1800)) == .finish(.region(displayID: 2, pixelRect: CGRect(x: 164, y: 1142, width: 200, height: 200))))
    }

    @Test func tinySelectionsAreRejected() {
        // 4 px is the smallest side: 2 pt at scale 2.
        var tooSmall = start()
        #expect(drag(&tooSmall, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 101, y: 101)) == .none)
        #expect(tooSmall.highlight == .none)
        var narrow = start()
        #expect(drag(&narrow, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 101.5, y: 300)) == .none)
        var flat = start()
        #expect(drag(&flat, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 101.5)) == .none)
        var smallest = start()
        #expect(drag(&smallest, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 102, y: 102)) == .finish(.region(displayID: 1, pixelRect: CGRect(x: 200, y: 1760, width: 4, height: 4))))
    }

    @Test func aClickWithoutDraggingSelectsNothing() {
        var interaction = start()
        #expect(interaction.mouseDown(at: CGPoint(x: 100, y: 100)) == .none)
        #expect(interaction.mouseUp(at: CGPoint(x: 100, y: 100)) == .none)
        #expect(interaction.highlight == .none)
    }

    @Test func aRejectedDragCanBeFollowedByAnotherOne() {
        var interaction = start()
        #expect(drag(&interaction, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 101, y: 101)) == .none)
        #expect(drag(&interaction, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 150)) == .finish(.region(displayID: 1, pixelRect: CGRect(x: 200, y: 1664, width: 200, height: 100))))
    }

    @Test func dragThatStartsOutsideEveryDisplayIsIgnored() {
        var interaction = start()
        #expect(interaction.mouseDown(at: CGPoint(x: -1000, y: 500)) == .none)
        interaction.mouseDragged(to: CGPoint(x: 100, y: 100))
        #expect(interaction.highlight == .none)
        #expect(interaction.mouseUp(at: CGPoint(x: 100, y: 100)) == .none)
    }

    @Test func dragEventsWithoutAPressAreIgnored() {
        var interaction = start()
        interaction.mouseDragged(to: CGPoint(x: 100, y: 100))
        #expect(interaction.highlight == .none)
        #expect(interaction.mouseUp(at: CGPoint(x: 100, y: 100)) == .none)
    }

    // MARK: Window mode

    @Test func spaceTogglesWindowModeOnlyWhereWindowsCanBeCaptured() {
        var both = start(.regionOrWindow)
        #expect(!both.isWindowMode)
        _ = both.keyDown(.space, pointer: CGPoint(x: 5, y: 5))
        #expect(both.isWindowMode)
        _ = both.keyDown(.space, pointer: CGPoint(x: 5, y: 5))
        #expect(!both.isWindowMode)
        for mode in [SelectionMode.region, .ocrRegion] {
            var regionOnly = start(mode)
            #expect(regionOnly.keyDown(.space, pointer: CGPoint(x: 5, y: 5)) == .none)
            #expect(!regionOnly.isWindowMode)
        }
    }

    @Test func spaceDuringADragIsIgnored() {
        var interaction = start()
        _ = interaction.mouseDown(at: CGPoint(x: 100, y: 100))
        interaction.mouseDragged(to: CGPoint(x: 200, y: 200))
        _ = interaction.keyDown(.space, pointer: CGPoint(x: 200, y: 200))
        #expect(!interaction.isWindowMode)
        #expect(interaction.mouseUp(at: CGPoint(x: 200, y: 200)) == .finish(.region(displayID: 1, pixelRect: CGRect(x: 200, y: 1564, width: 200, height: 200))))
    }

    @Test func hoveringHighlightsTheFrontmostCapturableWindowInAppKitCoordinates() {
        var interaction = start()
        _ = interaction.keyDown(.space, pointer: CGPoint(x: 5, y: 5))
        #expect(interaction.highlight == .none)
        // CG (200, 982 − 700 = 282) lies in window 12, which is in front of 13; window 11 (MyNotch) and the menu bar are skipped.
        interaction.pointerMoved(to: CGPoint(x: 200, y: 700))
        #expect(interaction.highlight == .window(rect: CGRect(x: 100, y: 582, width: 400, height: 300)))
        // CG (700, 982 − 600 = 382) is inside MyNotch's window 11 and the big window 13 behind it.
        interaction.pointerMoved(to: CGPoint(x: 700, y: 600))
        #expect(interaction.highlight == .window(rect: CGRect(x: 80, y: 302, width: 800, height: 600)))
        interaction.pointerMoved(to: CGPoint(x: 1400, y: 900))
        #expect(interaction.highlight == .none)
    }

    @Test func spaceHighlightsTheWindowUnderThePointerAtOnce() {
        var interaction = start()
        _ = interaction.keyDown(.space, pointer: CGPoint(x: 200, y: 700))
        #expect(interaction.highlight == .window(rect: CGRect(x: 100, y: 582, width: 400, height: 300)))
        _ = interaction.keyDown(.space, pointer: CGPoint(x: 200, y: 700))
        #expect(interaction.highlight == .none)
    }

    @Test func clickingCapturesTheWindowUnderThePointer() {
        var interaction = start()
        _ = interaction.keyDown(.space, pointer: CGPoint(x: 5, y: 5))
        interaction.pointerMoved(to: CGPoint(x: 200, y: 700))
        // The press alone captures nothing: the overlay takes the whole click, so no app below gets a stray release.
        #expect(interaction.mouseDown(at: CGPoint(x: 200, y: 700)) == .none)
        #expect(interaction.mouseUp(at: CGPoint(x: 200, y: 700)) == .finish(.window(12)))
    }

    @Test func releasingOverAnotherWindowCapturesNothing() {
        var interaction = start()
        _ = interaction.keyDown(.space, pointer: CGPoint(x: 5, y: 5))
        _ = interaction.mouseDown(at: CGPoint(x: 200, y: 700))
        #expect(interaction.mouseUp(at: CGPoint(x: 700, y: 600)) == .none)
        // The next click starts afresh.
        #expect(interaction.mouseUp(at: CGPoint(x: 200, y: 700)) == .none)
        _ = interaction.mouseDown(at: CGPoint(x: 700, y: 600))
        #expect(interaction.mouseUp(at: CGPoint(x: 700, y: 600)) == .finish(.window(13)))
    }

    @Test func clickingWhereThereIsNoWindowDoesNothing() {
        var interaction = start()
        _ = interaction.keyDown(.space, pointer: CGPoint(x: 5, y: 5))
        #expect(interaction.mouseDown(at: CGPoint(x: 1400, y: 900)) == .none)
        #expect(interaction.mouseUp(at: CGPoint(x: 1400, y: 900)) == .none)
        #expect(interaction.isWindowMode)
    }

    @Test func switchingModeDropsAPress() {
        var interaction = start()
        _ = interaction.keyDown(.space, pointer: CGPoint(x: 5, y: 5))
        _ = interaction.mouseDown(at: CGPoint(x: 200, y: 700))
        _ = interaction.keyDown(.space, pointer: CGPoint(x: 200, y: 700))
        _ = interaction.keyDown(.space, pointer: CGPoint(x: 200, y: 700))
        #expect(interaction.mouseUp(at: CGPoint(x: 200, y: 700)) == .none)
    }

    @Test func windowModeNeverStartsADrag() {
        var interaction = start()
        _ = interaction.keyDown(.space, pointer: CGPoint(x: 5, y: 5))
        _ = interaction.mouseDown(at: CGPoint(x: 1400, y: 900))
        interaction.mouseDragged(to: CGPoint(x: 1000, y: 500))
        #expect(interaction.mouseUp(at: CGPoint(x: 1000, y: 500)) == .none)
    }

    @Test func windowsTooSmallToSeeAreNotOffered() {
        let sliver = CapturableWindow(id: 20, ownerPID: 7, layer: 0, bounds: CGRect(x: 10, y: 10, width: 10, height: 400))
        var interaction = OverlayInteraction(mode: .regionOrWindow, displays: [primary], windows: [sliver], excludingPID: ownPID)
        _ = interaction.keyDown(.space, pointer: CGPoint(x: 15, y: 700))
        #expect(interaction.highlight == .none)
    }

    // MARK: Hints

    @Test func hintDescribesTheKeysThatApplyInTheCurrentMode() {
        var both = start(.regionOrWindow)
        #expect(both.hint.contains("Space") && both.hint.contains("Esc") && both.hint.contains("Return"))
        _ = both.keyDown(.space, pointer: .zero)
        #expect(both.hint.contains("cửa sổ") && both.hint.contains("Space"))
        #expect(!start(.region).hint.contains("Space"))
        #expect(!start(.ocrRegion).hint.contains("Space"))
        #expect(start(.ocrRegion).hint != start(.region).hint)
    }
}
