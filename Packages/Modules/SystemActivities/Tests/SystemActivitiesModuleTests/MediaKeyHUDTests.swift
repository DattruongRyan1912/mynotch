import AppKit
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import SystemActivitiesModule

@Suite struct MediaKeyHUDTests {
    let tap = FakeEventTap()
    let queue = FakeHardwareQueue()
    let changes = FakeHardwareChanges()
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
            tap: tap, queue: queue, changes: changes, volume: volume, brightness: brightness, keyboardLight: keyboardLight,
            isTrusted: { state.trusted }, scheduler: scheduler)
    }

    /// Starts the HUD without letting the hardware queue run, so the first look at the hardware is still pending.
    func startWithoutLooking() {
        let state = state
        hud.start(enabled: { state.selection }, onChange: { state.published.append($0) })
    }

    /// Starts the HUD and lets its first look at the hardware finish, so the keys it can take are known.
    func start() {
        startWithoutLooking()
        queue.drain()
    }

    /// A key press and the hardware work it queued, run to the end. True when the HUD swallowed it.
    @discardableResult
    func press(
        _ key: MediaKey, down: Bool = true, isRepeat: Bool = false, fine: Bool = false, modifiers: NSEvent.ModifierFlags = []
    ) -> Bool {
        let swallowed = tap.press(key, down: down, isRepeat: isRepeat, fine: fine, modifiers: modifiers)
        queue.drain()
        return swallowed
    }

    var published: [SystemActivityContent] { state.published }

    // MARK: volume

    @Test func volumeUpAndDownMoveOneSixteenthAndShowIt() {
        start()
        #expect(press(.volumeUp))
        #expect(volume.state == VolumeState(level: 0.5625, muted: false))
        #expect(press(.volumeDown))
        #expect(press(.volumeDown))
        #expect(volume.state == VolumeState(level: 0.4375, muted: false))
        #expect(published == [
            .volume(VolumeState(level: 0.5625, muted: false)),
            .volume(VolumeState(level: 0.5, muted: false)),
            .volume(VolumeState(level: 0.4375, muted: false)),
        ])
    }

    @Test func optionShiftMovesOneSixtyFourth() {
        start()
        #expect(press(.volumeUp, fine: true))
        #expect(volume.state?.level == 0.515625)
    }

    @Test func aHeldKeyKeepsMoving() {
        start()
        press(.volumeUp)
        press(.volumeUp, isRepeat: true)
        press(.volumeUp, isRepeat: true)
        #expect(volume.state?.level == 0.6875)
    }

    @Test func theKeyReleaseIsSwallowedLikeItsPressAndDoesNothing() {
        start()
        #expect(press(.volumeUp))
        let writes = volume.writeCount
        #expect(press(.volumeUp, down: false))
        #expect(volume.writeCount == writes)
        #expect(published.count == 1)
    }

    @Test func volumeStopsAtTheEnds() {
        start()
        volume.state = VolumeState(level: 1, muted: false)
        press(.volumeUp)
        #expect(volume.state?.level == 1)
        volume.state = VolumeState(level: 0, muted: false)
        press(.volumeDown)
        #expect(volume.state?.level == 0)
    }

    @Test func muteTogglesAndKeepsTheLevel() {
        start()
        #expect(press(.mute))
        #expect(volume.state == VolumeState(level: 0.5, muted: true))
        #expect(published.last == .volume(VolumeState(level: 0.5, muted: true)))
        #expect(press(.mute))
        #expect(volume.state == VolumeState(level: 0.5, muted: false))
        #expect(published.last == .volume(VolumeState(level: 0.5, muted: false)))
    }

    @Test func aVolumeKeyWhileMutedUnmutesAndMoves() {
        start()
        volume.state = VolumeState(level: 0.5, muted: true)
        press(.volumeUp)
        #expect(volume.state == VolumeState(level: 0.5625, muted: false))
        volume.state = VolumeState(level: 0.5, muted: true)
        press(.volumeDown)
        #expect(volume.state == VolumeState(level: 0.4375, muted: false))
    }

    @Test func aDeviceWithoutMuteLeavesTheMuteKeyToTheSystem() {
        volume.canMute = false
        start()
        #expect(!press(.mute))
        #expect(!press(.mute, down: false))
        #expect(volume.state?.muted == false)
        #expect(published.isEmpty)
        // The volume keys are still ours.
        #expect(press(.volumeUp))
    }

    // MARK: brightness and keyboard light

    @Test func brightnessKeysMoveOneSixteenthAndShowIt() {
        start()
        #expect(press(.brightnessUp))
        #expect(press(.brightnessUp, fine: true))
        #expect(press(.brightnessDown))
        #expect(brightness.writes == [0.5625, 0.578125, 0.5625])
        #expect(published.map(\.id) == ["brightness", "brightness", "brightness"])
    }

    @Test func brightnessStopsAtTheEnds() {
        start()
        brightness.level = 1
        press(.brightnessUp)
        #expect(brightness.level == 1)
        brightness.level = 0
        press(.brightnessDown)
        #expect(brightness.level == 0)
        #expect(published.last == .brightness(0))
    }

    @Test func keyboardLightKeysMoveOneSixteenthAndShowIt() {
        start()
        #expect(press(.keyboardLightUp))
        #expect(keyboardLight.level == 0.5625)
        #expect(press(.keyboardLightDown))
        #expect(press(.keyboardLightDown))
        #expect(keyboardLight.level == 0.4375)
        #expect(published.last == .keyboardLight(0.4375))
    }

    @Test func theKeyboardLightToggleSwitchesOffAndBackToTheLevelItHad() {
        start()
        keyboardLight.level = 0.75
        #expect(press(.keyboardLightToggle))
        #expect(keyboardLight.level == 0)
        #expect(published.last == .keyboardLight(0))
        #expect(press(.keyboardLightToggle))
        #expect(keyboardLight.level == 0.75)
        #expect(published.last == .keyboardLight(0.75))
    }

    @Test func theKeyboardLightToggleFromOffWithNothingRememberedGoesToFull() {
        start()
        keyboardLight.level = 0
        press(.keyboardLightToggle)
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
        #expect(!press(key))
        #expect(!press(key, down: false))
        #expect(published.isEmpty)
        #expect((volume.writeCount, brightness.writes, keyboardLight.writes) == (0, [], []))
    }

    @Test func onlyTheEnabledKindsAreConsumed() {
        state.selection = MediaKeySelection(volume: false, brightness: true, keyboardLight: false)
        start()
        #expect(!press(.volumeUp))
        #expect(press(.brightnessUp))
        #expect(!press(.keyboardLightUp))
    }

    @Test func theSubTogglesAreReadAtEveryKeyPress() {
        start()
        #expect(press(.brightnessUp))
        state.selection.brightness = false
        #expect(!press(.brightnessUp))
        state.selection.brightness = true
        #expect(press(.brightnessUp))
    }

    @Test func everyKindOffConsumesNothing() {
        state.selection = MediaKeySelection(volume: false, brightness: false, keyboardLight: false)
        start()
        #expect(![.volumeUp, .mute, .brightnessDown, .keyboardLightToggle].contains { press($0) })
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
        volume.state = nil
        brightness.level = nil
        keyboardLight.level = nil
        start()
        for key in [MediaKey.volumeUp, .volumeDown, .mute, .brightnessUp, .brightnessDown, .keyboardLightUp, .keyboardLightDown, .keyboardLightToggle] {
            #expect(!press(key))
            #expect(!press(key, down: false))
        }
        #expect(published.isEmpty)
    }

    @Test func oneMissingControlDoesNotTakeTheOthersWithIt() {
        brightness.level = nil
        start()
        #expect(!press(.brightnessUp))
        #expect(press(.volumeUp))
        #expect(press(.keyboardLightUp))
    }

    // MARK: tap lifecycle

    @Test func startingInstallsTheTapAndStoppingRemovesIt() {
        #expect(!tap.isInstalled)
        start()
        #expect(tap.isInstalled)
        hud.stop()
        #expect(!tap.isInstalled)
        #expect(!press(.volumeUp))
        #expect(volume.writeCount == 0)
    }

    @Test func startingAgainReplacesTheTap() {
        start()
        start()
        #expect(tap.isInstalled)
        #expect(tap.installCount == 2)
        #expect(tap.uninstallCount >= 1)
        #expect(press(.volumeUp))
        #expect(published.count == 1)
    }

    @Test func noTapAndNoRetryWithoutAccessibilityUntilItIsGranted() {
        state.trusted = false
        start()
        // Not even an attempt: creating the tap would be refused, and the keys stay the system's.
        #expect(tap.installCount == 0)
        #expect(!press(.volumeUp))

        scheduler.advance(by: .seconds(2))
        #expect(tap.installCount == 0)
        state.trusted = true
        scheduler.advance(by: .milliseconds(1_999))
        #expect(!tap.isInstalled)
        scheduler.advance(by: .milliseconds(1))
        #expect(tap.isInstalled)
        queue.drain()
        #expect(press(.volumeUp))
        // Installed: the waiting for the permission is over, and only the slow check of the tap is left.
        #expect(scheduler.pendingCount == 1)
        scheduler.advance(by: .seconds(60))
        #expect(tap.installCount == 1)
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
        #expect(press(.volumeUp))
    }

    @Test func aTapSwitchedOffAfterAccessibilityWasTakenAwayWaitsForItToComeBack() {
        start()
        state.trusted = false
        #expect(!tap.send(.disabled))
        #expect(tap.reenableCount == 0)
        #expect(!tap.isInstalled)
        #expect(!press(.volumeUp))

        state.trusted = true
        scheduler.advance(by: .seconds(2))
        #expect(tap.isInstalled)
        queue.drain()
        #expect(press(.volumeUp))
    }

    // MARK: the volume monitor's echo

    @Test func theVolumeTheHUDJustSetIsRecognisedWhenTheMonitorReportsIt() {
        start()
        press(.volumeUp)
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
        press(.volumeUp)
        hud.stop()
        #expect(!hud.isEcho(VolumeState(level: 0.5625, muted: false)))
    }

    // MARK: the tap callback decides from what it already knows

    @Test func startingAsksTheHardwareNothingUntilTheQueueRuns() {
        startWithoutLooking()
        #expect(queue.pendingCount == 1)
        #expect((volume.readCount, brightness.readCount, keyboardLight.readCount) == (0, 0, 0))
    }

    @Test func theCallbackTouchesNoHardwareAndTheQueueDoesTheWorkForPressesOnly() {
        start()
        let reads = (volume.readCount, brightness.readCount, keyboardLight.readCount)
        let keys: [MediaKey] = [.volumeUp, .mute, .brightnessUp, .keyboardLightToggle]
        for key in keys {
            #expect(tap.press(key))
            #expect(tap.press(key, down: false))
        }
        #expect((volume.readCount, brightness.readCount, keyboardLight.readCount) == reads)
        #expect(volume.writeCount == 0 && brightness.writes.isEmpty && keyboardLight.writes.isEmpty)
        #expect(published.isEmpty)
        // One piece of work per press; the releases queue none.
        #expect(queue.pendingCount == keys.count)
        queue.drain()
        #expect(published.count == keys.count)
    }

    @Test func nothingIsTakenBeforeTheFirstLookAtTheHardwareHasFinished() {
        startWithoutLooking()
        #expect(!tap.press(.volumeUp))
        #expect(!tap.press(.brightnessUp))
        #expect(!tap.press(.keyboardLightUp))
        queue.drain()
        #expect(published.isEmpty)
        #expect(tap.press(.volumeUp))
    }

    @Test func pressesAreHandledInTheOrderTheyCame() {
        start()
        tap.press(.volumeUp)
        tap.press(.volumeUp)
        tap.press(.volumeDown)
        #expect(queue.pendingCount == 3)
        queue.drain()
        #expect(published == [
            .volume(VolumeState(level: 0.5625, muted: false)),
            .volume(VolumeState(level: 0.625, muted: false)),
            .volume(VolumeState(level: 0.5625, muted: false)),
        ])
    }

    @Test func noLookIsMadeAndNothingIsListenedToWhileThereIsNoTap() {
        state.trusted = false
        start()
        #expect(queue.pendingCount == 0)
        #expect(!changes.isListening)
        #expect((volume.readCount, brightness.readCount, keyboardLight.readCount) == (0, 0, 0))
    }

    @Test func anAnswerThatArrivesAfterStopShowsNothing() {
        start()
        #expect(tap.press(.volumeUp))
        hud.stop()
        queue.drain()
        #expect(published.isEmpty)
        #expect(!hud.isEcho(VolumeState(level: 0.5625, muted: false)))
    }

    @Test func anAnswerFromAnEarlierRunDoesNotShowInTheNextOne() {
        start()
        #expect(tap.press(.brightnessUp))
        start()
        #expect(published.isEmpty)
    }

    // MARK: a release and the repeats go the way their press went

    @Test func aReleaseIsSwallowedOnlyWhenItsPressWas() {
        start()
        state.selection.volume = false
        #expect(!press(.volumeUp))
        state.selection.volume = true
        // The press went to the system, so the release does too, though the volume keys are ours by now.
        #expect(!press(.volumeUp, down: false))
        #expect(volume.writeCount == 0)

        #expect(press(.volumeUp))
        state.selection.volume = false
        #expect(press(.volumeUp, down: false))
        // A release with no press before it is not ours to swallow.
        #expect(!press(.volumeUp, down: false))
    }

    @Test func theRepeatsOfAHeldKeyGoTheWayItsPressWent() {
        start()
        #expect(press(.volumeUp))
        state.selection.volume = false
        #expect(press(.volumeUp, isRepeat: true))
        #expect(press(.volumeUp, down: false))

        #expect(!press(.volumeUp))
        state.selection.volume = true
        #expect(!press(.volumeUp, isRepeat: true))
        #expect(!press(.volumeUp, down: false))
    }

    @Test func aRepeatWhoseKeyWasNotSeenGoingDownIsDecidedOnItsOwn() {
        start()
        #expect(press(.volumeUp, isRepeat: true))
        #expect(press(.volumeUp, down: false))
    }

    @Test func aReleaseAfterMacOSSwitchedTheTapOffAndItWasSwitchedBackOnIsStillSwallowed() {
        start()
        #expect(press(.volumeUp))
        #expect(!tap.send(.disabled))
        #expect(press(.volumeUp, down: false))
    }

    @Test func aReleaseAfterTheTapWasMadeAgainGoesToTheSystem() {
        start()
        #expect(press(.volumeUp))
        tap.killed = true
        tap.revivable = false
        scheduler.advance(by: MediaKeyHUD.checkInterval)
        queue.drain()
        // The new tap never saw the press.
        #expect(!press(.volumeUp, down: false))
    }

    // MARK: keys with other modifiers

    @Test(arguments: [NSEvent.ModifierFlags.command, .control, [.command, .option, .shift], [.control, .shift]])
    func aKeyWithCommandOrControlHeldIsLeftToTheSystem(modifiers: NSEvent.ModifierFlags) {
        start()
        #expect(!press(.brightnessUp, modifiers: modifiers))
        #expect(!press(.volumeDown, modifiers: modifiers))
        #expect(!press(.brightnessUp, down: false, modifiers: modifiers))
        #expect(brightness.writes.isEmpty && volume.writeCount == 0)
    }

    // MARK: a write that cannot happen

    @Test func aWriteThatFailsShowsNothingAndTheKeysGoBackToTheSystemFromThenOn() {
        start()
        // The device went away after the last look, so the HUD still thinks the volume keys are its own.
        volume.state = nil
        #expect(press(.volumeUp))
        #expect(published.isEmpty)
        #expect(!press(.volumeUp))
        #expect(!press(.volumeDown))
        #expect(!press(.mute))
        // The other kinds are not touched by it.
        #expect(press(.brightnessUp))
    }

    @Test func aControlThatRefusesWhatIsWrittenIsGivenBackToTheSystemToo() {
        start()
        keyboardLight.refusesWrites = true
        #expect(press(.keyboardLightUp))
        #expect(published.isEmpty)
        #expect(!press(.keyboardLightUp))
    }

    @Test func aKindGivenBackIsTakenAgainAtTheNextLookWhenItWorks() {
        start()
        brightness.refusesWrites = true
        press(.brightnessUp)
        #expect(!press(.brightnessUp))
        brightness.refusesWrites = false
        changes.fire()
        queue.drain()
        #expect(press(.brightnessUp))
        #expect(brightness.writes == [0.5625])
    }

    // MARK: looking at what the keys can do again

    @Test func theKeysAreLookedAtAgainWhenTheHardwareChangesNotAtEveryPress() {
        start()
        let before = (volume.readCount, brightness.readCount, keyboardLight.readCount)
        brightness.level = nil
        changes.fire()
        queue.drain()
        #expect(brightness.refreshCount >= 1)
        #expect(!press(.brightnessUp))
        brightness.level = 0.5
        changes.fire()
        queue.drain()
        #expect(press(.brightnessUp))
        #expect(volume.readCount > before.0)
    }

    @Test func aPressDoesNotLookAgainAtWhatTheKeysCanDo() {
        start()
        let refreshes = (brightness.refreshCount, keyboardLight.refreshCount)
        press(.brightnessUp)
        press(.keyboardLightUp)
        press(.volumeUp)
        #expect((brightness.refreshCount, keyboardLight.refreshCount) == refreshes)
    }

    @Test func theSlowCheckLooksAtWhatTheKeysCanDoAgain() {
        start()
        keyboardLight.level = nil
        scheduler.advance(by: MediaKeyHUD.checkInterval - .milliseconds(1))
        #expect(queue.pendingCount == 0)
        scheduler.advance(by: .milliseconds(1))
        #expect(queue.pendingCount == 1)
        queue.drain()
        #expect(!press(.keyboardLightUp))
    }

    @Test func theChangesAreListenedToExactlyWhileTheTapIsUp() {
        #expect(!changes.isListening)
        start()
        #expect(changes.isListening)
        hud.stop()
        #expect(!changes.isListening)

        state.trusted = false
        start()
        #expect(!changes.isListening)
        state.trusted = true
        scheduler.advance(by: .seconds(2))
        #expect(changes.isListening)

        // Accessibility taken away while it runs.
        state.trusted = false
        tap.send(.disabled)
        #expect(!changes.isListening)
    }

    // MARK: a tap that died without a word

    @Test func aHealthyTapIsLeftAloneAtEveryCheck() {
        start()
        scheduler.advance(by: .seconds(120))
        #expect(tap.installCount == 1)
        #expect(tap.reenableCount == 0)
        #expect(tap.isAlive)
    }

    @Test func aTapMacOSSwitchedOffWithoutSayingSoIsSwitchedBackOnAtTheNextCheck() {
        start()
        tap.killed = true
        scheduler.advance(by: MediaKeyHUD.checkInterval - .milliseconds(1))
        #expect(tap.reenableCount == 0)
        scheduler.advance(by: .milliseconds(1))
        #expect(tap.reenableCount == 1)
        #expect(tap.isAlive)
        #expect(tap.installCount == 1)
        queue.drain()
        #expect(press(.volumeUp))
    }

    @Test func aTapThatWillNotComeBackIsMadeAgain() {
        start()
        tap.killed = true
        tap.revivable = false
        scheduler.advance(by: MediaKeyHUD.checkInterval)
        #expect(tap.installCount == 2)
        #expect(tap.isAlive)
        queue.drain()
        #expect(press(.volumeUp))
        // And it is watched again.
        tap.killed = true
        scheduler.advance(by: MediaKeyHUD.checkInterval)
        #expect(tap.installCount == 3)
    }

    @Test func aTapLeftWithoutAccessibilityIsDroppedAtTheNextCheckAndMadeAgainWhenItIsBack() {
        start()
        state.trusted = false
        tap.killed = true
        scheduler.advance(by: MediaKeyHUD.checkInterval)
        #expect(tap.reenableCount == 0)
        #expect(!tap.isInstalled)
        #expect(!press(.volumeUp))

        state.trusted = true
        scheduler.advance(by: .seconds(2))
        #expect(tap.isInstalled)
        queue.drain()
        #expect(press(.volumeUp))
    }

    @Test func stoppingEndsTheChecks() {
        start()
        hud.stop()
        #expect(scheduler.pendingCount == 0)
    }

    // MARK: selection

    @Test func theSelectionDefaultsToEverything() {
        let selection = MediaKeySelection()
        #expect([MediaKey.Target.volume, .brightness, .keyboardLight].allSatisfy(selection.contains))
        #expect(!MediaKeySelection(volume: false).contains(.volume))
    }
}
