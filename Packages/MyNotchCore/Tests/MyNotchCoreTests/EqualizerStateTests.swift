import Foundation
import Observation
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct EqualizerStateTests {
    /// Keeps the isolated suite alive for as long as the test runs, and reopens it as a new launch would.
    final class Launches {
        let defaults = makeIsolatedDefaults()
        func launch() -> EqualizerState { EqualizerState(settings: SettingsStore(defaults: defaults)) }
    }

    private let flat = Array(repeating: 0.0, count: 10)

    @Test func seedsThreeDefaultsOnFirstRun() {
        let state = Launches().launch()
        #expect(state.profiles.map(\.name) == ["Nhạc", "Phim", "Họp"])
        #expect(state.selected?.name == "Nhạc")
        #expect(state.isEnabled == false)
    }

    @Test func loudnessIsOffByDefaultAndSurvivesALaunch() {
        let launches = Launches()
        let first = launches.launch()
        #expect(first.isLoudnessEnabled == false)
        first.isLoudnessEnabled = true
        #expect(launches.launch().isLoudnessEnabled)
    }

    @Test func defaultCurvesMatchTheDesign() {
        let profiles = EQProfile.defaults()
        #expect(profiles.map(\.gains) == [
            [4, 3, 1.5, 0, -1, -1, 0, 1.5, 3, 4],
            [5, 4, 2, 0, 0, 1.5, 2.5, 2, 1, 0],
            [-6, -4, -2, 0, 1, 2.5, 4, 3.5, 1, 0],
        ])
        #expect(profiles.map(\.preamp) == [-4, -4, -2])
        #expect(EQProfile.frequencies == [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000])
        #expect(EQProfile.gainRange == -12...12)
        #expect(Set(profiles.map(\.id)).count == 3)
    }

    @Test func seededProfilesKeepTheirIdsAndSelectionAcrossLaunches() {
        let launches = Launches()
        let first = launches.launch()
        let ids = first.profiles.map(\.id)
        first.select(ids[2])
        let second = launches.launch()
        #expect(second.profiles.map(\.id) == ids)
        #expect(second.selectedID == ids[2])
    }

    @Test func emptyListStaysEmptyAfterReload() {
        let launches = Launches()
        let state = launches.launch()
        for profile in state.profiles { state.delete(profile.id) }
        state.isEnabled = true
        #expect(state.profiles.isEmpty)
        #expect(state.selectedID == nil)

        let reloaded = launches.launch()
        #expect(reloaded.profiles.isEmpty)
        #expect(reloaded.selected == nil)
        #expect(reloaded.isEnabled)
        #expect(reloaded.activeProfile?.gains == flat)
        #expect(reloaded.activeProfile?.preamp == 0)
    }

    @Test func settingsOnAnEmptyListDoNothingAndDoNotCrash() {
        let state = Launches().launch()
        for profile in state.profiles { state.delete(profile.id) }
        state.setGain(6, band: 3)
        state.setPreamp(-3)
        state.resetSelectedToFlat()
        state.select(UUID())
        #expect(state.profiles.isEmpty)
        #expect(state.selectedID == nil)
    }

    @Test func deletingSelectedSelectsFirstRemaining() {
        let state = Launches().launch()
        let ids = state.profiles.map(\.id)
        state.select(ids[1])
        state.delete(ids[1])
        #expect(state.profiles.map(\.id) == [ids[0], ids[2]])
        #expect(state.selectedID == ids[0])

        state.delete(ids[0])
        #expect(state.selectedID == ids[2])
        state.delete(ids[2])
        #expect(state.selectedID == nil)
    }

    @Test func deletingAnotherProfileKeepsTheSelection() {
        let state = Launches().launch()
        let ids = state.profiles.map(\.id)
        state.delete(ids[2])
        #expect(state.selectedID == ids[0])
        state.delete(UUID())
        #expect(state.profiles.count == 2)
    }

    @Test func renameRejectsBlankAndOverlong() {
        let state = Launches().launch()
        let id = state.profiles[0].id
        #expect(state.rename(id, to: "  ") == false)
        #expect(state.rename(id, to: String(repeating: "a", count: 41)) == false)
        #expect(state.profiles[0].name == "Nhạc")

        #expect(state.rename(id, to: "  Phòng khách \n") == true)
        #expect(state.profiles[0].name == "Phòng khách")
        #expect(state.rename(id, to: String(repeating: "a", count: 40)) == true)
        #expect(state.rename(UUID(), to: "Không có") == false)
    }

    @Test func renamePersists() {
        let launches = Launches()
        let state = launches.launch()
        state.rename(state.profiles[1].id, to: "Xem phim")
        #expect(launches.launch().profiles.map(\.name) == ["Nhạc", "Xem phim", "Họp"])
    }

    @Test func setGainClampsAndPersists() {
        let launches = Launches()
        let state = launches.launch()
        state.setGain(15, band: 0)
        state.setGain(-20, band: 9)
        state.setGain(2.5, band: 4)
        #expect(state.selected?.gains[0] == 12)
        #expect(state.selected?.gains[9] == -12)

        let reloaded = launches.launch()
        #expect(reloaded.selected?.gains[0] == 12)
        #expect(reloaded.selected?.gains[9] == -12)
        #expect(reloaded.selected?.gains[4] == 2.5)
    }

    @Test func setGainIgnoresABandThatDoesNotExistAndNaN() {
        let state = Launches().launch()
        let before = state.selected
        state.setGain(5, band: -1)
        state.setGain(5, band: 10)
        #expect(state.selected == before)

        state.setGain(.nan, band: 2)
        state.setPreamp(.nan)
        #expect(state.selected?.gains[2] == 0)
        #expect(state.selected?.preamp == 0)
    }

    @Test func setPreampClampsAndPersists() {
        let launches = Launches()
        let state = launches.launch()
        state.setPreamp(30)
        #expect(state.selected?.preamp == 12)
        state.setPreamp(-30)
        #expect(launches.launch().selected?.preamp == -12)
    }

    @Test func resetSelectedToFlatKeepsNameAndLeavesTheOthers() {
        let state = Launches().launch()
        let others = Array(state.profiles.dropFirst())
        let id = state.profiles[0].id
        state.resetSelectedToFlat()
        #expect(state.selected?.id == id)
        #expect(state.selected?.name == "Nhạc")
        #expect(state.selected?.gains == flat)
        #expect(state.selected?.preamp == 0)
        #expect(Array(state.profiles.dropFirst()) == others)
    }

    @Test func activeProfileIsNilWhenDisabled() {
        let state = Launches().launch()
        #expect(state.activeProfile == nil)
        state.isEnabled = true
        #expect(state.activeProfile == state.selected)
        state.isEnabled = false
        #expect(state.activeProfile == nil)
    }

    @Test func enabledPersistsAtOnce() {
        let launches = Launches()
        launches.launch().isEnabled = true
        #expect(launches.launch().isEnabled)
    }

    @Test func addProfileCopiesSelectedAndSelectsIt() throws {
        let launches = Launches()
        let state = launches.launch()
        state.select(state.profiles[2].id)
        let source = try #require(state.selected)

        let added = try #require(state.addProfile(named: " Của tôi "))
        #expect(added.name == "Của tôi")
        #expect(added.gains == source.gains)
        #expect(added.preamp == source.preamp)
        #expect(added.id != source.id)
        #expect(state.profiles.count == 4)
        #expect(state.profiles.last == added)
        #expect(state.selectedID == added.id)
        #expect(launches.launch().selectedID == added.id)
    }

    @Test func addProfileOnAnEmptyListStartsFlat() throws {
        let state = Launches().launch()
        for profile in state.profiles { state.delete(profile.id) }
        let added = try #require(state.addProfile(named: "Mới"))
        #expect(added.gains == flat)
        #expect(added.preamp == 0)
        #expect(state.selectedID == added.id)
    }

    @Test func addProfileRejectsABadName() {
        let state = Launches().launch()
        #expect(state.addProfile(named: "   ") == nil)
        #expect(state.addProfile(named: String(repeating: "a", count: 41)) == nil)
        #expect(state.profiles.count == 3)
    }

    @Test func clampedFixesWrongBandCount() {
        var profile = EQProfile.flat(named: "x")
        profile.gains = [1, 2, 3, 4, 5, 6, 7]
        #expect(profile.clamped().gains == [1, 2, 3, 4, 5, 6, 7, 0, 0, 0])

        profile.gains = Array(1...12).map(Double.init)
        #expect(profile.clamped().gains == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    }

    @Test func clampedKeepsEveryValueInRange() {
        var profile = EQProfile.flat(named: "x")
        profile.gains = [20, -20, .infinity, -.infinity, .nan, 0, 0, 0, 0, 0]
        profile.preamp = 99
        let fixed = profile.clamped()
        #expect(fixed.gains == [12, -12, 12, -12, 0, 0, 0, 0, 0, 0])
        #expect(fixed.preamp == 12)
        #expect(fixed.id == profile.id)
        #expect(fixed.name == "x")
    }

    @Test func profilesLoadedFromStorageAreClamped() {
        let launches = Launches()
        var bad = EQProfile.flat(named: "Hỏng")
        bad.gains = [50, 1]
        bad.preamp = -50
        SettingsStore(defaults: launches.defaults).set(Optional([bad]), for: EqualizerState.profilesKey)

        let state = launches.launch()
        #expect(state.profiles.count == 1)
        #expect(state.profiles[0].gains == [12, 1, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(state.profiles[0].preamp == -12)
    }

    @Test func aSelectionThatNoLongerExistsFallsBackToTheFirstProfile() {
        let launches = Launches()
        let store = SettingsStore(defaults: launches.defaults)
        store.set(Optional(EQProfile.defaults()), for: EqualizerState.profilesKey)
        store.set(Optional(UUID()), for: EqualizerState.selectedKey)

        let state = EqualizerState(settings: store)
        #expect(state.selected?.name == "Nhạc")
    }

    @Test func settingKeysLiveUnderTheAppNamespace() {
        #expect(EqualizerState.profilesKey.name == "app.equalizer.profiles")
        #expect(EqualizerState.selectedKey.name == "app.equalizer.selected")
        #expect(EqualizerState.enabledKey.name == "app.equalizer.enabled")
        #expect(EqualizerState.enabledKey.defaultValue == false)
    }

    @Test func availabilityAndEditorAreNotStored() {
        let launches = Launches()
        let state = launches.launch()
        nonisolated(unsafe) var opened = 0
        state.isAvailable = true
        state.openEditor = { opened += 1 }
        state.openEditor?()
        #expect(opened == 1)

        let reloaded = launches.launch()
        #expect(reloaded.isAvailable == false)
        #expect(reloaded.openEditor == nil)
    }

    @Test func changesNotifyObservers() {
        let state = Launches().launch()
        nonisolated(unsafe) var notifications = 0
        func observe(_ read: () -> Void) {
            withObservationTracking(read) { notifications += 1 }
        }
        observe { _ = state.activeProfile }
        state.isEnabled = true
        #expect(notifications == 1)

        observe { _ = state.activeProfile }
        state.setGain(3, band: 0)
        #expect(notifications == 2)

        observe { _ = state.isAvailable }
        state.isAvailable = true
        #expect(notifications == 3)
    }

    @Test func theSystemAudioPermissionSaysItAlsoServesTheEqualizer() {
        #expect(Permission.systemAudio.summary.contains("chỉnh âm (EQ)"))
        #expect(Permission.systemAudio.instruction.contains("tab Âm thanh"))
    }
}
