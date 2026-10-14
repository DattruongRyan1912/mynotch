import MyNotchCore
import Testing
@testable import SystemActivitiesModule

/// The HUD inside the module: the settings, the permission, and the activities the keys produce.
extension SystemActivitiesModuleTests {
    func settleTapInstalled() async { await settle { fakes.tap.isInstalled } }

    @Test func theHUDIsOffByDefaultSoTheKeysStayTheSystems() async {
        await start()
        #expect(fakes.tap.installCount == 0)
        #expect(!fakes.tap.press(.volumeUp))
        #expect(fakes.systemVolume.writeCount == 0)
        #expect(entries.isEmpty)
    }

    @Test func turningItOnInstallsTheTapAndOffRemovesIt() async {
        await start()
        setting("replaceHUD", true)
        await settleTapInstalled()
        #expect(fakes.tap.isInstalled)
        setting("replaceHUD", false)
        await settle { !fakes.tap.isInstalled }
        #expect(!fakes.tap.isInstalled)
        #expect(!fakes.tap.press(.volumeUp))
    }

    @Test func aModuleStartedWithItOnTakesTheKeysAtOnce() async {
        setting("replaceHUD", true)
        await start()
        #expect(fakes.tap.isInstalled)
    }

    @Test func stoppingTheModuleRemovesTheTap() async {
        setting("replaceHUD", true)
        await start()
        #expect(fakes.tap.isInstalled)
        await harness.registry.setEnabled(false, for: "system")
        #expect(!fakes.tap.isInstalled)
    }

    @Test func aKeyPressChangesTheVolumeAndShowsTheBarForOneAndAHalfSeconds() async {
        setting("replaceHUD", true)
        await start()
        // The configured duration is for the other activities, not for this bar.
        harness.settings.set(4.0, for: SettingKey("module.system.durationSeconds", default: 2.5, clampedTo: 1...6))
        #expect(fakes.tap.press(.volumeUp))
        #expect(fakes.systemVolume.state?.level == 0.5625)
        #expect(entries.map(\.id) == ["system/volume"])
        #expect(entries.first?.activity.expiresAfter == .milliseconds(1_500))
        harness.scheduler.advance(by: .milliseconds(1_499))
        #expect(entries.count == 1)
        harness.scheduler.advance(by: .milliseconds(1))
        #expect(entries.isEmpty)
    }

    @Test func eachKindHasItsOwnActivityThatIsUpdatedInPlace() async {
        setting("replaceHUD", true)
        await start()
        fakes.tap.press(.brightnessUp)
        fakes.tap.press(.keyboardLightUp)
        fakes.tap.press(.volumeUp)
        #expect(Set(entries.map(\.id)) == ["system/brightness", "system/keyboardLight", "system/volume"])
        fakes.tap.press(.brightnessUp)
        fakes.tap.press(.brightnessUp)
        #expect(entries.count == 3)
        #expect(entries.allSatisfy { $0.activity.expiresAfter == .milliseconds(1_500) && $0.activity.priority == .normal })
    }

    @Test func aHeldKeyKeepsTheBarUpAndItGoesOneAndAHalfSecondsAfterTheLastPress() async {
        setting("replaceHUD", true)
        await start()
        for _ in 0..<4 {
            fakes.tap.press(.brightnessUp)
            harness.scheduler.advance(by: .seconds(1))
        }
        #expect(entries.map(\.id) == ["system/brightness"])
        harness.scheduler.advance(by: .milliseconds(500))
        #expect(entries.isEmpty)
    }

    @Test(arguments: [
        ("hudVolume", MediaKey.volumeUp), ("hudBrightness", .brightnessUp), ("hudKeyboardLight", .keyboardLightUp),
    ])
    func eachSubToggleSwitchesItsKeysBackToTheSystem(name: String, key: MediaKey) async {
        setting("replaceHUD", true)
        await start()
        // On by default, like the main setting being on.
        #expect(fakes.tap.press(key))
        setting(name, false)
        #expect(!fakes.tap.press(key))
        #expect(!fakes.tap.press(key, down: false))
        setting(name, true)
        #expect(fakes.tap.press(key))
    }

    @Test func aSubToggleDoesNotNeedTheTapToBeInstalledAgain() async {
        setting("replaceHUD", true)
        await start()
        setting("hudBrightness", false)
        setting("hudBrightness", true)
        #expect(fakes.tap.installCount == 1)
    }

    @Test func withoutAccessibilityTheKeysStayAndTheTapComesOnceItIsGranted() async {
        fakes.trusted = false
        setting("replaceHUD", true)
        await start()
        #expect(fakes.tap.installCount == 0)
        #expect(!fakes.tap.press(.volumeUp))
        harness.scheduler.advance(by: .seconds(2))
        #expect(!fakes.tap.isInstalled)

        fakes.trusted = true
        harness.scheduler.advance(by: .seconds(2))
        #expect(fakes.tap.isInstalled)
        #expect(fakes.tap.press(.volumeUp))
    }

    @Test func theVolumeMonitorReportingTheHUDsOwnChangeDoesNotKeepTheBarUpLonger() async {
        setting("replaceHUD", true)
        await start()
        fakes.tap.press(.volumeUp)
        harness.scheduler.advance(by: .seconds(1))
        // CoreAudio tells the monitor about the change the HUD just made.
        fakes.volume.send(level: 0.5625)
        harness.scheduler.advance(by: .milliseconds(500))
        #expect(entries.isEmpty)
    }

    @Test func aVolumeChangeFromElsewhereStillShowsForTheConfiguredDuration() async {
        setting("replaceHUD", true)
        await start()
        fakes.tap.press(.volumeUp)
        fakes.volume.send(level: 0.2)
        #expect(entries.first?.activity.expiresAfter == .seconds(2.5))
        // And the HUD's own value is no longer an echo once somebody else changed it.
        harness.scheduler.advance(by: .seconds(3))
        fakes.volume.send(level: 0.5625)
        #expect(entries.map(\.id) == ["system/volume"])
    }

    @Test func withTheHUDOffTheVolumeMonitorIsUnchanged() async {
        await start()
        fakes.volume.send(level: 0.4)
        #expect(entries.first?.activity.expiresAfter == .seconds(2.5))
    }

    @Test func theHUDWorksWhileTheVolumeActivityIsOff() async {
        setting("volume", false)
        setting("replaceHUD", true)
        await start()
        #expect(!fakes.volume.isRunning)
        #expect(fakes.tap.press(.volumeUp))
        #expect(entries.map(\.id) == ["system/volume"])
    }
}
