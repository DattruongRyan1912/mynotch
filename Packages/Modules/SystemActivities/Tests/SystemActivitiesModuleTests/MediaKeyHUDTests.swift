import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import SystemActivitiesModule

@Suite struct MediaKeyHUDTests {
    let tap = FakeEventTap()
    let volume = FakeVolumeControl()
    let brightness = FakeLevelControl()
    let keyboardLight = FakeLevelControl()
    let scheduler = ManualScheduler()
    let state = HUDState()
    let hud: MediaKeyHUD

    /// What the tests change while the HUD runs.
    final class HUDState {
        var trusted = true
        var selection = MediaKeySelection()
        var published: [SystemActivityContent] = []
    }

    init() {
        let state = state
        hud = MediaKeyHUD(
            tap: tap, volume: volume, brightness: brightness, keyboardLight: keyboardLight,
            isTrusted: { state.trusted }, scheduler: scheduler)
    }

    func start() {
        let state = state
        hud.start(enabled: { state.selection }, onChange: { state.published.append($0) })
    }

    var published: [SystemActivityContent] { state.published }

    // MARK: volume

    @Test func volumeUpAndDownMoveOneSixteenthAndShowIt() {
        start()
        #expect(tap.press(.volumeUp))
        #expect(volume.state == VolumeState(level: 0.5625, muted: false))
        #expect(tap.press(.volumeDown))
        #expect(tap.press(.volumeDown))
        #expect(volume.state == VolumeState(level: 0.4375, muted: false))
        #expect(published == [
            .volume(VolumeState(level: 0.5625, muted: false)),
            .volume(VolumeState(level: 0.5, muted: false)),
            .volume(VolumeState(level: 0.4375, muted: false)),
        ])
    }

    @Test func optionShiftMovesOneSixtyFourth() {
        start()
        #expect(tap.press(.volumeUp, fine: true))
        #expect(volume.state?.level == 0.515625)
    }

    @Test func aHeldKeyKeepsMoving() {
        start()
        tap.press(.volumeUp)
        tap.press(.volumeUp, isRepeat: true)
        tap.press(.volumeUp, isRepeat: true)
        #expect(volume.state?.level == 0.6875)
    }

    @Test func theKeyReleaseIsSwallowedToo() {
        start()
        #expect(tap.press(.volumeUp, down: false))
        #expect(volume.writeCount == 0)
        #expect(published.isEmpty)
    }

    @Test func volumeStopsAtTheEnds() {
        start()
        volume.state = VolumeState(level: 1, muted: false)
        tap.press(.volumeUp)
        #expect(volume.state?.level == 1)
        volume.state = VolumeState(level: 0, muted: false)
        tap.press(.volumeDown)
        #expect(volume.state?.level == 0)
    }

    @Test func muteTogglesAndKeepsTheLevel() {
        start()
        #expect(tap.press(.mute))
        #expect(volume.state == VolumeState(level: 0.5, muted: true))
        #expect(published.last == .volume(VolumeState(level: 0.5, muted: true)))
        #expect(tap.press(.mute))
        #expect(volume.state == VolumeState(level: 0.5, muted: false))
        #expect(published.last == .volume(VolumeState(level: 0.5, muted: false)))
    }

    @Test func aVolumeKeyWhileMutedUnmutesAndMoves() {
        start()
        volume.state = VolumeState(level: 0.5, muted: true)
        tap.press(.volumeUp)
        #expect(volume.state == VolumeState(level: 0.5625, muted: false))
        volume.state = VolumeState(level: 0.5, muted: true)
        tap.press(.volumeDown)
        #expect(volume.state == VolumeState(level: 0.4375, muted: false))
    }

    @Test func aDeviceWithoutMuteLeavesTheMuteKeyToTheSystem() {
        start()
        volume.canMute = false
        #expect(!tap.press(.mute))
        #expect(!tap.press(.mute, down: false))
        #expect(volume.state?.muted == false)
        #expect(published.isEmpty)
        // The volume keys are still ours.
        #expect(tap.press(.volumeUp))
    }

    // MARK: brightness and keyboard light

    @Test func brightnessKeysMoveOneSixteenthAndShowIt() {
        start()
        #expect(tap.press(.brightnessUp))
        #expect(tap.press(.brightnessUp, fine: true))
        #expect(tap.press(.brightnessDown))
        #expect(brightness.writes == [0.5625, 0.578125, 0.5625])
        #expect(published.map(\.id) == ["brightness", "brightness", "brightness"])
    }

    @Test func brightnessStopsAtTheEnds() {
        start()
        brightness.level = 1
        tap.press(.brightnessUp)
        #expect(brightness.level == 1)
        brightness.level = 0
        tap.press(.brightnessDown)
        #expect(brightness.level == 0)
        #expect(published.last == .brightness(0))
    }

    @Test func keyboardLightKeysMoveOneSixteenthAndShowIt() {
        start()
        #expect(tap.press(.keyboardLightUp))
        #expect(keyboardLight.level == 0.5625)
        #expect(tap.press(.keyboardLightDown))
        #expect(tap.press(.keyboardLightDown))
        #expect(keyboardLight.level == 0.4375)
        #expect(published.last == .keyboardLight(0.4375))
    }

    @Test func theKeyboardLightToggleSwitchesOffAndBackToTheLevelItHad() {
        start()
        keyboardLight.level = 0.75
        #expect(tap.press(.keyboardLightToggle))
        #expect(keyboardLight.level == 0)
        #expect(published.last == .keyboardLight(0))
        #expect(tap.press(.keyboardLightToggle))
        #expect(keyboardLight.level == 0.75)
        #expect(published.last == .keyboardLight(0.75))
    }

    @Test func theKeyboardLightToggleFromOffWithNothingRememberedGoesToFull() {
        start()
        keyboardLight.level = 0
        tap.press(.keyboardLightToggle)
        #expect(keyboardLight.level == 1)
    }

    // MARK: which events are consumed

    nonisolated static let selections: [(MediaKeySelection, MediaKey)] = [
        (MediaKeySelection(volume: false), .volumeUp), (MediaKeySelection(volume: false), .volumeDown),
        (MediaKeySelection(volume: false), .mute),
        (MediaKeySelection(brightness: false), .brightnessUp), (MediaKeySelection(brightness: false), .brightnessDown),
        (MediaKeySelection(keyboardLight: false), .keyboardLightUp), (MediaKeySelection(keyboardLight: false), .keyboardLightDown),
        (MediaKeySelection(keyboardLight: false), .keyboardLightToggle),
    ]

    @Test(arguments: selections)
    func aKeyWhoseSubToggleIsOffPassesThroughTouchingNothing(selection: MediaKeySelection, key: MediaKey) {
        state.selection = selection
        start()
        #expect(!tap.press(key))
        #expect(!tap.press(key, down: false))
        #expect(published.isEmpty)
        #expect((volume.writeCount, brightness.writes, keyboardLight.writes) == (0, [], []))
    }

    @Test func onlyTheEnabledKindsAreConsumed() {
        state.selection = MediaKeySelection(volume: false, brightness: true, keyboardLight: false)
        start()
        #expect(!tap.press(.volumeUp))
        #expect(tap.press(.brightnessUp))
        #expect(!tap.press(.keyboardLightUp))
    }

    @Test func theSubTogglesAreReadAtEveryKeyPress() {
        start()
        #expect(tap.press(.brightnessUp))
        state.selection.brightness = false
        #expect(!tap.press(.brightnessUp))
        state.selection.brightness = true
        #expect(tap.press(.brightnessUp))
    }

    @Test func everyKindOffConsumesNothing() {
        state.selection = MediaKeySelection(volume: false, brightness: false, keyboardLight: false)
        start()
        #expect(![.volumeUp, .mute, .brightnessDown, .keyboardLightToggle].contains { tap.press($0) })
    }

    @Test func eventsThatAreNotMediaKeysPassThrough() {
        start()
        #expect(!tap.send(.systemDefined(subtype: 7, data1: 0x000A00, modifiers: [])))
        // Play/pause is the Media module's key.
        #expect(!tap.send(.systemDefined(subtype: 8, data1: (16 << 16) | (0xA << 8), modifiers: [])))
        #expect(published.isEmpty)
    }

    // MARK: a control that is not there

    @Test func aMissingControlLeavesItsKeysToTheSystem() {
        start()
        volume.state = nil
        brightness.level = nil
        keyboardLight.level = nil
        for key in [MediaKey.volumeUp, .volumeDown, .mute, .brightnessUp, .brightnessDown, .keyboardLightUp, .keyboardLightDown, .keyboardLightToggle] {
            #expect(!tap.press(key))
            #expect(!tap.press(key, down: false))
        }
        #expect(published.isEmpty)
    }

    @Test func oneMissingControlDoesNotTakeTheOthersWithIt() {
        start()
        brightness.level = nil
        #expect(!tap.press(.brightnessUp))
        #expect(tap.press(.volumeUp))
        #expect(tap.press(.keyboardLightUp))
    }

    // MARK: tap lifecycle

    @Test func startingInstallsTheTapAndStoppingRemovesIt() {
        #expect(!tap.isInstalled)
        start()
        #expect(tap.isInstalled)
        hud.stop()
        #expect(!tap.isInstalled)
        #expect(!tap.press(.volumeUp))
        #expect(volume.writeCount == 0)
    }

    @Test func startingAgainReplacesTheTap() {
        start()
        start()
        #expect(tap.isInstalled)
        #expect(tap.installCount == 2)
        #expect(tap.uninstallCount >= 1)
        #expect(tap.press(.volumeUp))
        #expect(published.count == 1)
    }

    @Test func noTapAndNoRetryWithoutAccessibilityUntilItIsGranted() {
        state.trusted = false
        start()
        // Not even an attempt: creating the tap would be refused, and the keys stay the system's.
        #expect(tap.installCount == 0)
        #expect(!tap.press(.volumeUp))

        scheduler.advance(by: .seconds(2))
        #expect(tap.installCount == 0)
        state.trusted = true
        scheduler.advance(by: .milliseconds(1_999))
        #expect(!tap.isInstalled)
        scheduler.advance(by: .milliseconds(1))
        #expect(tap.isInstalled)
        #expect(tap.press(.volumeUp))
        // Installed: the checking stops.
        #expect(scheduler.pendingCount == 0)
    }

    @Test func aTapMacOSRefusesIsTriedAgain() {
        tap.canInstall = false
        start()
        #expect(tap.installCount == 1)
        scheduler.advance(by: .seconds(2))
        #expect(tap.installCount == 2)
        tap.canInstall = true
        scheduler.advance(by: .seconds(2))
        #expect(tap.isInstalled)
        #expect(tap.installCount == 3)
        scheduler.advance(by: .seconds(10))
        #expect(tap.installCount == 3)
    }

    @Test func stoppingCancelsTheWaitForAccessibility() {
        state.trusted = false
        start()
        #expect(scheduler.pendingCount == 1)
        hud.stop()
        #expect(scheduler.pendingCount == 0)
        state.trusted = true
        scheduler.advance(by: .seconds(10))
        #expect(tap.installCount == 0)
    }

    @Test func aTapMacOSSwitchedOffIsSwitchedBackOn() {
        start()
        #expect(!tap.send(.disabled))
        #expect(tap.reenableCount == 1)
        #expect(tap.isInstalled)
        // Still ours afterwards.
        #expect(tap.press(.volumeUp))
    }

    @Test func aTapSwitchedOffAfterAccessibilityWasTakenAwayWaitsForItToComeBack() {
        start()
        state.trusted = false
        #expect(!tap.send(.disabled))
        #expect(tap.reenableCount == 0)
        #expect(!tap.isInstalled)
        #expect(!tap.press(.volumeUp))

        state.trusted = true
        scheduler.advance(by: .seconds(2))
        #expect(tap.isInstalled)
        #expect(tap.press(.volumeUp))
    }

    // MARK: the volume monitor's echo

    @Test func theVolumeTheHUDJustSetIsRecognisedWhenTheMonitorReportsIt() {
        start()
        tap.press(.volumeUp)
        let set = VolumeState(level: 0.5625, muted: false)
        #expect(hud.isEcho(set))
        #expect(hud.isEcho(set))
        // Any other volume is somebody else's change, and makes the HUD forget its own.
        #expect(!hud.isEcho(VolumeState(level: 0.3, muted: false)))
        #expect(!hud.isEcho(set))
    }

    @Test func nothingIsAnEchoBeforeTheHUDSetAnything() {
        start()
        #expect(!hud.isEcho(VolumeState(level: 0.5, muted: false)))
    }

    @Test func stoppingForgetsTheEcho() {
        start()
        tap.press(.volumeUp)
        hud.stop()
        #expect(!hud.isEcho(VolumeState(level: 0.5625, muted: false)))
    }

    // MARK: selection

    @Test func theSelectionDefaultsToEverything() {
        let selection = MediaKeySelection()
        #expect([MediaKey.Target.volume, .brightness, .keyboardLight].allSatisfy(selection.contains))
        #expect(!MediaKeySelection(volume: false).contains(.volume))
    }
}
