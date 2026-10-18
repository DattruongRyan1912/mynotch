import CoreGraphics
import Testing
@testable import ScreenshotModule

/// What the overlay's answer becomes when the person records instead of capturing, and the overlay's recording modes.
@Suite struct RecordingSelectionTests {
    /// A MacBook display at the origin (scale 2) and a 4K monitor above it (scale 1), as in the geometry tests.
    let primary = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)
    let external = DisplayInfo(id: 2, frame: CGRect(x: -1164, y: 982, width: 3840, height: 2160), scale: 1)
    var displays: [DisplayInfo] { [primary, external] }
    let ownPID: pid_t = 100

    var windows: [CapturableWindow] {
        [
            CapturableWindow(id: 12, ownerPID: 7, layer: 0, bounds: CGRect(x: 100, y: 100, width: 400, height: 300)),
            CapturableWindow(id: 13, ownerPID: 8, layer: 0, bounds: CGRect(x: 80, y: 80, width: 800, height: 600)),
        ]
    }

    // MARK: From the overlay's answer to a region

    @Test func aWholeScreenIsTheDisplayItself() throws {
        let region = try #require(RecordingSelection.region(for: .fullScreen(displayID: 2), displays: displays, windows: []))
        #expect(region.display == external)
        #expect(region.pixelRect == CGRect(x: 0, y: 0, width: 3840, height: 2160))
    }

    @Test func aDraggedRegionKeepsItsPixelsExactly() throws {
        // The overlay snapped the drag to pixels; none of them may shift on the way to the recording.
        let region = try #require(RecordingSelection.region(
            for: .region(displayID: 1, pixelRect: CGRect(x: 201, y: 333, width: 640, height: 480)), displays: displays, windows: []
        ))
        #expect(region.display == primary)
        #expect(region.pixelRect == CGRect(x: 201, y: 333, width: 640, height: 480))
    }

    @Test func anOddRegionLosesOnePixelToTheEvenSizeTheEncoderNeeds() throws {
        let region = try #require(RecordingSelection.region(
            for: .region(displayID: 1, pixelRect: CGRect(x: 10, y: 11, width: 301, height: 201)), displays: displays, windows: []
        ))
        #expect(region.pixelRect == CGRect(x: 10, y: 11, width: 300, height: 200))
    }

    @Test func aRegionPastTheDisplayIsKeptInsideIt() throws {
        let region = try #require(RecordingSelection.region(
            for: .region(displayID: 1, pixelRect: CGRect(x: 2800, y: 1900, width: 400, height: 400)), displays: displays, windows: []
        ))
        // The display is 3024×1964 pixels.
        #expect(region.pixelRect == CGRect(x: 2800, y: 1900, width: 224, height: 64))
    }

    @Test func aRegionWithNothingOnTheDisplayIsNothing() {
        #expect(RecordingSelection.region(
            for: .region(displayID: 1, pixelRect: CGRect(x: 5000, y: 5000, width: 100, height: 100)), displays: displays, windows: []
        ) == nil)
        #expect(RecordingSelection.region(for: .region(displayID: 9, pixelRect: CGRect(x: 0, y: 0, width: 100, height: 100)), displays: displays, windows: []) == nil)
        #expect(RecordingSelection.region(for: .fullScreen(displayID: 9), displays: displays, windows: []) == nil)
    }

    @Test func aWindowIsItsFrameAsItIsNow() throws {
        // CG (100, 100, 400×300) on the 982-pt primary display is AppKit y 582; at scale 2 the pixels start at (200, 200).
        let region = try #require(RecordingSelection.region(for: .window(12), displays: displays, windows: windows))
        #expect(region.display == primary)
        #expect(region.pixelRect == CGRect(x: 200, y: 200, width: 800, height: 600))
    }

    @Test func aWindowPartlyOffItsDisplayIsCutAtTheEdge() throws {
        // CG (1300, 800, 400×300) hangs off the right and the bottom of the primary display; its centre is still on it.
        let hanging = CapturableWindow(id: 30, ownerPID: 7, layer: 0, bounds: CGRect(x: 1300, y: 800, width: 400, height: 300))
        let region = try #require(RecordingSelection.region(for: .window(30), displays: displays, windows: [hanging]))
        #expect(region.display == primary)
        #expect(region.pixelRect == CGRect(x: 2600, y: 1600, width: 424, height: 364))
    }

    @Test func aWindowWhoseCentreIsOnNoDisplayIsNothing() {
        let away = CapturableWindow(id: 31, ownerPID: 7, layer: 0, bounds: CGRect(x: 5000, y: 5000, width: 400, height: 300))
        #expect(RecordingSelection.region(for: .window(31), displays: displays, windows: [away]) == nil)
    }

    @Test func aWindowThatIsGoneIsNothing() {
        #expect(RecordingSelection.region(for: .window(99), displays: displays, windows: windows) == nil)
    }

    @Test func theWholeDisplayOfAnEvenPixelCountNeedsNoChange() throws {
        let region = try #require(RecordingRegion(display: primary, pixelRect: CGRect(x: 0, y: 0, width: 3024, height: 1964)))
        #expect(region == RecordingRegion(fullScreen: primary))
    }

    // MARK: The overlay's modes for recording

    func start(_ mode: SelectionMode) -> OverlayInteraction {
        OverlayInteraction(mode: mode, displays: displays, windows: windows, excludingPID: ownPID)
    }

    @Test(arguments: [SelectionMode.recordRegion, .recordRegionOrWindow, .recordWindow])
    func escapeCancelsInEveryRecordingMode(mode: SelectionMode) {
        var interaction = start(mode)
        #expect(interaction.keyDown(.escape, pointer: CGPoint(x: 100, y: 100)) == .cancel)
    }

    @Test func recordingARegionIsDraggedAndReturnTakesTheWholeScreen() {
        var interaction = start(.recordRegion)
        #expect(!interaction.isWindowMode)
        #expect(interaction.keyDown(.space, pointer: CGPoint(x: 5, y: 5)) == .none && !interaction.isWindowMode)
        _ = interaction.mouseDown(at: CGPoint(x: 100, y: 100))
        interaction.mouseDragged(to: CGPoint(x: 300, y: 300))
        #expect(interaction.mouseUp(at: CGPoint(x: 300, y: 300)) == .finish(.region(displayID: 1, pixelRect: CGRect(x: 200, y: 1364, width: 400, height: 400))))
        var whole = start(.recordRegion)
        #expect(whole.keyDown(.returnKey, pointer: CGPoint(x: 100, y: 100)) == .finish(.fullScreen(displayID: 1)))
    }

    @Test func recordingAWindowStartsOnWindowsAndSpaceDoesNotLeaveThem() {
        var interaction = start(.recordWindow)
        #expect(interaction.isWindowMode)
        #expect(interaction.keyDown(.space, pointer: CGPoint(x: 200, y: 700)) == .none)
        #expect(interaction.isWindowMode)
        interaction.pointerMoved(to: CGPoint(x: 200, y: 700))
        #expect(interaction.highlight == .window(rect: CGRect(x: 100, y: 582, width: 400, height: 300)))
        #expect(interaction.mouseDown(at: CGPoint(x: 200, y: 700)) == .none)
        #expect(interaction.mouseUp(at: CGPoint(x: 200, y: 700)) == .finish(.window(12)))
    }

    @Test func recordingAWindowHasNoWholeScreenKey() {
        var interaction = start(.recordWindow)
        #expect(interaction.keyDown(.returnKey, pointer: CGPoint(x: 100, y: 100)) == .none)
    }

    @Test func recordingAWindowNeverStartsADrag() {
        var interaction = start(.recordWindow)
        _ = interaction.mouseDown(at: CGPoint(x: 1400, y: 900))
        interaction.mouseDragged(to: CGPoint(x: 1000, y: 500))
        #expect(interaction.mouseUp(at: CGPoint(x: 1000, y: 500)) == .none)
    }

    @Test func spaceSwitchesBetweenRegionAndWindowWhenRecordingEitherOne() {
        var both = start(.recordRegionOrWindow)
        #expect(!both.isWindowMode)
        _ = both.keyDown(.space, pointer: CGPoint(x: 5, y: 5))
        #expect(both.isWindowMode)
        _ = both.keyDown(.space, pointer: CGPoint(x: 5, y: 5))
        #expect(!both.isWindowMode)
        #expect(both.keyDown(.returnKey, pointer: CGPoint(x: 100, y: 100)) == .finish(.fullScreen(displayID: 1)))
    }

    @Test func theHintsSayRecordAndNeverCapture() {
        var both = start(.recordRegionOrWindow)
        #expect(both.hint.contains("quay") && both.hint.contains("Space") && both.hint.contains("Return") && both.hint.contains("Esc"))
        _ = both.keyDown(.space, pointer: .zero)
        #expect(both.hint.contains("cửa sổ") && both.hint.contains("quay") && both.hint.contains("Space"))
        for mode in [SelectionMode.recordRegionOrWindow, .recordRegion, .recordWindow] {
            #expect(!start(mode).hint.contains("chụp"))
            #expect(start(mode).hint.contains("Esc"))
        }
        #expect(!start(.recordRegion).hint.contains("Space"))
        #expect(!start(.recordWindow).hint.contains("Space") && !start(.recordWindow).hint.contains("Return"))
    }
}
