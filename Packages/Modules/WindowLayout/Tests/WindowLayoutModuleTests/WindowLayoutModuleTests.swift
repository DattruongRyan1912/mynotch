import CoreGraphics
import Foundation
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import WindowLayoutModule

/// The module in a real registry with a fake notch interface, fake mouse and keyboard, fake Accessibility windows and a
/// fake preview: nothing real is watched, shown or moved.
/// Stands in for the trackpad: a test never feels anything.
final class HapticRecorder: HapticPerformer {
    private(set) var performed: [Haptic] = []
    func perform(_ haptic: Haptic) { performed.append(haptic) }
}

@MainActor
final class ModuleFixture {
    let events = FakeDragEvents()
    let window = FakeWindow(frame: CGRect(x: 600, y: 300, width: 800, height: 600))
    let probe: FakeWindowProbe
    let preview = FakePreview()
    let haptics = HapticRecorder()
    let interface: NotchInterface
    let module: WindowLayoutModule
    let harness: RegistryHarness
    private var time: TimeInterval = 0

    init() {
        let probe = FakeWindowProbe(window)
        let preview = preview
        self.probe = probe
        interface = NotchInterface(performer: haptics)
        module = WindowLayoutModule(
            events: events, probe: probe,
            screens: { SnapScreens(screens: [SnapScreen(id: 1, visibleFrame: SessionFixture.macBookVisible)], primaryHeight: 982) },
            makePreview: { preview }, interface: interface
        )
        harness = RegistryHarness([module])
        interface.notches = [NotchDisplay(
            id: 1, screenFrame: SessionFixture.macBook.frame, geometry: NotchGeometry(screen: SessionFixture.macBook, config: NotchLayoutConfig())
        )]
        harness.permissions.statuses[.accessibility] = .granted
    }

    var settings: ModuleSettings { harness.settingsEnvironment(for: "windows")!.settings }
    var keys: WindowLayoutKeys { WindowLayoutKeys(settings) }
    func enable() async { await harness.registry.setEnabled(true, for: "windows") }
    func disable() async { await harness.registry.setEnabled(false, for: "windows") }

    func drag(to point: CGPoint) {
        window.drag(to: CGPoint(x: point.x - 200, y: 982 - point.y - 10))
        time += 0.05
        events.send(.dragged(point, time: time))
    }

    /// Presses, drags the window towards the notch and over the first tile.
    func dragOverFirstTile(of count: Int = SnapLayout.allCases.count) {
        events.send(.down)
        for x in [400.0, 420, 440] { drag(to: CGPoint(x: x, y: 500)) }
        drag(to: SessionFixture.nearMacBook)
        drag(to: firstTile(of: count))
    }

    func firstTile(of count: Int = SnapLayout.allCases.count) -> CGPoint {
        let tile = SnapTiles.frames(count: count, in: SessionFixture.macBookContent)[0]
        return CGPoint(x: tile.midX, y: tile.midY)
    }
}

@Suite struct WindowLayoutModuleTests {
    @Test func descriptor() {
        let descriptor = ModuleFixture().module.descriptor
        #expect(descriptor.id == "windows")
        #expect(descriptor.displayName == "Chia cửa sổ")
        #expect(descriptor.systemImage == "rectangle.split.2x2")
        #expect(descriptor.defaultEnabled)
        #expect(descriptor.order == 950)
        // Accessibility is asked for in Settings but never stops the module from starting.
        #expect(descriptor.permissions.isEmpty)
        #expect(descriptor.optionalPermissions == [.accessibility])
        #expect(descriptor.permissionReasons[.accessibility]?.isEmpty == false)
    }

    @Test func itHasNoTabOfItsOwn() async {
        let fixture = ModuleFixture()
        #expect(fixture.module.makeTab() == nil)
        await fixture.enable()
        #expect(fixture.harness.registry.tabs.isEmpty)
    }

    @Test func itListensOnlyWhileItRuns() async {
        let fixture = ModuleFixture()
        #expect(!fixture.events.isStarted, "off until the user turns it on")
        await fixture.enable()
        #expect(fixture.harness.registry.state(of: "windows") == .running)
        #expect(fixture.events.isStarted)
        await fixture.disable()
        #expect(!fixture.events.isStarted)
    }

    @Test func itStartsWithoutAccessibilityAndSnapsOnceItIsGranted() async {
        let fixture = ModuleFixture()
        fixture.harness.permissions.statuses[.accessibility] = .denied
        await fixture.enable()
        #expect(fixture.harness.registry.state(of: "windows") == .running)
        fixture.dragOverFirstTile()
        #expect(fixture.harness.presenter.toastCount == 0)
        fixture.events.send(.up(fixture.firstTile()))
        // The grant needs no restart: it is read at the next press.
        fixture.harness.permissions.statuses[.accessibility] = .granted
        fixture.dragOverFirstTile()
        #expect(fixture.harness.presenter.toastCount == 1)
    }

    @Test func aWindowDroppedOnATileIsMovedThereAfterTheNotchOpenedAndClosed() async {
        let fixture = ModuleFixture()
        await fixture.enable()
        fixture.dragOverFirstTile()
        #expect(fixture.harness.presenter.toastCount == 1, "the notch opened with the tiles")
        #expect(fixture.preview.frame == CGRect(x: 0, y: 0, width: 756, height: 945))
        fixture.events.send(.up(fixture.firstTile()))
        #expect(fixture.harness.presenter.closeCount == 1)
        #expect(fixture.window.setFrames.isEmpty)
        fixture.harness.scheduler.advance(by: .milliseconds(200))
        #expect(fixture.window.setFrames == [CGRect(x: 0, y: 37, width: 756, height: 945)])
    }

    @Test func theGapAndTheLayoutsAreReadWhenTheyAreUsedNotWhenTheModuleStarts() async {
        let fixture = ModuleFixture()
        await fixture.enable()
        fixture.settings.set(.large, for: fixture.keys.gap)
        fixture.settings.set(["leftHalf", "focus"], for: fixture.keys.layouts)
        fixture.dragOverFirstTile(of: 2)
        // 16 from the edges and, on the side facing the right half, another 8: half of the gap between two windows.
        #expect(fixture.preview.frame == CGRect(x: 16, y: 16, width: 732, height: 913))
        fixture.events.send(.up(fixture.firstTile(of: 2)))
        fixture.harness.scheduler.advance(by: .milliseconds(200))
        #expect(fixture.window.setFrames == [CGRect(x: 16, y: 53, width: 732, height: 913)])
    }

    @Test func turningTheModuleOffDuringADragClosesTheNotchAndMovesNothing() async {
        let fixture = ModuleFixture()
        await fixture.enable()
        fixture.dragOverFirstTile()
        await fixture.disable()
        #expect(fixture.harness.presenter.closeCount == 1)
        #expect(!fixture.preview.isVisible)
        #expect(fixture.preview.isDismissed)
        fixture.events.send(.up(fixture.firstTile()))
        fixture.harness.scheduler.advance(by: .milliseconds(200))
        #expect(fixture.window.setFrames.isEmpty)
    }

    @Test func turningItOffWithNothingOpenLeavesTheNotchAlone() async {
        let fixture = ModuleFixture()
        await fixture.enable()
        await fixture.disable()
        #expect(fixture.harness.presenter.closeCount == 0)
    }

    @Test func itWorksAgainAfterBeingTurnedOffAndOn() async {
        let fixture = ModuleFixture()
        await fixture.enable()
        await fixture.disable()
        await fixture.enable()
        fixture.dragOverFirstTile()
        fixture.events.send(.up(fixture.firstTile()))
        fixture.harness.scheduler.advance(by: .milliseconds(200))
        #expect(fixture.window.setFrames.count == 1)
    }

    // MARK: the notice

    @Test func aWindowThatKeepsALargerSizeIsToldSoThroughTheNotch() async {
        let fixture = ModuleFixture()
        fixture.window.minimum = CGSize(width: 1040, height: 0)
        await fixture.enable()
        fixture.dragOverFirstTile()
        fixture.events.send(.up(fixture.firstTile()))
        #expect(fixture.harness.presenter.toastCount == 1, "only the tiles so far")
        fixture.harness.scheduler.advance(by: .milliseconds(200))
        #expect(fixture.window.current?.width == 1040)
        #expect(fixture.harness.presenter.toastCount == 2, "then the notice")
    }

    @Test func aWindowThatFitsItsZoneGetsNoNotice() async {
        let fixture = ModuleFixture()
        await fixture.enable()
        fixture.dragOverFirstTile()
        fixture.events.send(.up(fixture.firstTile()))
        fixture.harness.scheduler.advance(by: .milliseconds(200))
        #expect(fixture.window.setFrames.count == 1)
        #expect(fixture.harness.presenter.toastCount == 1)
    }

    // MARK: the tap on the trackpad

    @Test func aWindowSnappedIntoATileTapsTheTrackpadWithAnAlignment() async {
        let fixture = ModuleFixture()
        await fixture.enable()
        fixture.dragOverFirstTile()
        fixture.events.send(.up(fixture.firstTile()))
        #expect(fixture.haptics.performed.isEmpty, "not before the window has moved")
        fixture.harness.scheduler.advance(by: .milliseconds(200))
        #expect(fixture.window.setFrames.count == 1)
        #expect(fixture.haptics.performed == [.alignment])
    }

    @Test func theHapticsSettingIsRespected() async {
        let fixture = ModuleFixture()
        await fixture.enable()
        fixture.interface.hapticsEnabled = false
        fixture.dragOverFirstTile()
        fixture.events.send(.up(fixture.firstTile()))
        fixture.harness.scheduler.advance(by: .milliseconds(200))
        #expect(fixture.window.setFrames.count == 1, "the window is moved all the same")
        #expect(fixture.haptics.performed.isEmpty)
    }

    @Test func aDragThatSnapsNothingNeverTapsTheTrackpad() async {
        let fixture = ModuleFixture()
        await fixture.enable()
        fixture.dragOverFirstTile()
        await fixture.disable()
        fixture.events.send(.up(fixture.firstTile()))
        fixture.harness.scheduler.advance(by: .milliseconds(200))
        #expect(fixture.haptics.performed.isEmpty)
    }

    @Test func theNotchesComeFromTheInterfaceAtTheTimeOfTheDrag() async {
        let fixture = ModuleFixture()
        await fixture.enable()
        fixture.interface.notches = []
        fixture.dragOverFirstTile()
        #expect(fixture.harness.presenter.toastCount == 0)
    }

    // MARK: settings

    @Test func theSettingsHaveRowsWhetherOrNotItRuns() {
        let fixture = ModuleFixture()
        #expect(fixture.module.makeSettingsView(fixture.harness.settingsEnvironment(for: "windows")!) != nil)
    }

    @Test func settingsDefaultToAllLayoutsAndNoGap() {
        let fixture = ModuleFixture()
        let options = fixture.keys.options(fixture.settings)
        #expect(options.layouts == SnapLayout.allCases)
        #expect(options.gap == .none)
    }

    @Test func aGapThatIsNotZeroEightOrSixteenFallsBackToNone() {
        let fixture = ModuleFixture()
        // A number the picker never writes, as the setting's own JSON.
        fixture.harness.settings.set(12, for: SettingKey<Int>("module.windows.gap", default: 0))
        #expect(fixture.keys.options(fixture.settings).gap == .none)
        fixture.harness.settings.set(8, for: SettingKey<Int>("module.windows.gap", default: 0))
        #expect(fixture.keys.options(fixture.settings).gap == .small)
    }

    @Test func switchingALayoutOffKeepsTheOthersAndTheLastOneCannotGo() {
        var options = SnapOptions(storedLayouts: [], gap: .none)
        let withoutFocus = options.storedLayouts(setting: .focus, to: false)
        #expect(withoutFocus == [
            "leftHalf", "rightHalf", "topHalf", "bottomHalf", "fullScreen",
            "leftTwoThirds", "rightTwoThirds", "quarters", "thirds"
        ])
        options = SnapOptions(storedLayouts: ["thirds"], gap: .none)
        #expect(options.storedLayouts(setting: .thirds, to: false) == ["thirds"], "at least one stays")
        #expect(options.storedLayouts(setting: .leftHalf, to: true) == ["leftHalf", "thirds"], "kept in the tiles' order")
    }
}
