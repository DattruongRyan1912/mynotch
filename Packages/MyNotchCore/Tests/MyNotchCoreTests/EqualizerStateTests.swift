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
        #expect(state.profiles.map(\.name) == ["Nhạc", "Phim", "Họp", "Deep Bass (eqMac)"])
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
            [14.0, 10.0, 7.2, 2.7, 0.4, 0.7, -0.5, 0.0, 1.7, 1.4],
        ])
        #expect(profiles.map(\.preamp) == [0, 0, 0, 0])
        #expect(EQProfile.frequencies == [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000])
        #expect(EQProfile.gainRange == -24...24)
        #expect(EQProfile.preampRange == -12...12)
        #expect(Set(profiles.map(\.id)).count == 4)
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
        let emptyDefaults = makeIsolatedDefaults()
        let emptySettings = SettingsStore(defaults: emptyDefaults)
        emptySettings.set(Optional([EQProfile]()), for: EqualizerState.profilesKey)
        let state = EqualizerState(settings: emptySettings)
        state.isEnabled = true
        #expect(state.profiles.isEmpty)
        #expect(state.selectedID == nil)

        let reloaded = EqualizerState(settings: emptySettings)
        #expect(reloaded.profiles.isEmpty)
        #expect(reloaded.selected == nil)
        #expect(reloaded.isEnabled)
        #expect(reloaded.activeProfile?.gains == flat)
        #expect(reloaded.activeProfile?.preamp == 0)
    }

    @Test func settingsOnAnEmptyListDoNothingAndDoNotCrash() {
        let emptyDefaults = makeIsolatedDefaults()
        let emptySettings = SettingsStore(defaults: emptyDefaults)
        emptySettings.set(Optional([EQProfile]()), for: EqualizerState.profilesKey)
        let state = EqualizerState(settings: emptySettings)
        state.setGain(6, band: 3)
        state.setPreamp(-3)
        state.resetSelectedToFlat()
        state.select(UUID())
        #expect(state.profiles.isEmpty)
        #expect(state.selectedID == nil)
    }

    @Test func deletingSelectedSelectsFirstRemaining() {
        let state = Launches().launch()
        guard let c1 = state.addFlatProfile(named: "C1"),
              let c2 = state.addFlatProfile(named: "C2"),
              let c3 = state.addFlatProfile(named: "C3") else {
            Issue.record("Failed to create custom profiles")
            return
        }
        let ids = [c1.id, c2.id, c3.id]
        state.select(ids[1])
        state.delete(ids[1])
        #expect(state.selectedID == state.profiles.first?.id)

        state.delete(ids[0])
        #expect(state.selectedID == state.profiles.first?.id)
        state.delete(ids[2])
        #expect(state.profiles.contains(where: { ids.contains($0.id) }) == false)
    }

    @Test func deletingAnotherProfileKeepsTheSelection() {
        let state = Launches().launch()
        guard let c1 = state.addFlatProfile(named: "Custom Selected"),
              let c2 = state.addFlatProfile(named: "Custom Other") else {
            Issue.record("Failed to create custom profiles")
            return
        }
        state.select(c1.id)
        let initialCount = state.profiles.count
        state.delete(c2.id)
        #expect(state.selectedID == c1.id)
        #expect(state.profiles.count == initialCount - 1)
        state.delete(UUID())
        #expect(state.profiles.count == initialCount - 1)
    }

    @Test func renameRejectsBlankAndOverlong() {
        let state = Launches().launch()
        guard let custom = state.addFlatProfile(named: "Gốc") else {
            Issue.record("Failed to create custom profile")
            return
        }
        let id = custom.id
        #expect(state.rename(id, to: "  ") == false)
        #expect(state.rename(id, to: String(repeating: "a", count: 41)) == false)
        #expect(state.profiles.first(where: { $0.id == id })?.name == "Gốc")

        #expect(state.rename(id, to: "  Phòng khách \n") == true)
        #expect(state.profiles.first(where: { $0.id == id })?.name == "Phòng khách")
        #expect(state.rename(id, to: String(repeating: "a", count: 40)) == true)
        #expect(state.rename(UUID(), to: "Không có") == false)
    }

    @Test func renamePersists() {
        let launches = Launches()
        let state = launches.launch()
        guard let custom = state.addFlatProfile(named: "Ban đầu") else {
            Issue.record("Failed to create custom profile")
            return
        }
        state.rename(custom.id, to: "Đã sửa")
        #expect(launches.launch().profiles.first(where: { $0.id == custom.id })?.name == "Đã sửa")
    }

    @Test func setGainClampsAndPersists() {
        let launches = Launches()
        let state = launches.launch()
        state.setGain(30, band: 0)
        state.setGain(-30, band: 9)
        state.setGain(2.5, band: 4)
        #expect(state.selected?.gains[0] == 24)
        #expect(state.selected?.gains[9] == -24)

        let reloaded = launches.launch()
        #expect(reloaded.selected?.gains[0] == 24)
        #expect(reloaded.selected?.gains[9] == -24)
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

    @Test func setGainClampsTo24WhileSetPreampClampsTo12() {
        let state = Launches().launch()
        state.setGain(30, band: 0)
        #expect(state.selected?.gains[0] == 24.0)
        state.setGain(-30, band: 9)
        #expect(state.selected?.gains[9] == -24.0)
        state.setPreamp(24)
        #expect(state.selected?.preamp == 12.0)
        state.setPreamp(-24)
        #expect(state.selected?.preamp == -12.0)
    }

    @Test func migratesDeepBassPresetOnceForExistingUsersWithoutPollutingDeletedOrCustomLists() {
        let legacyDefaults = makeIsolatedDefaults()
        let legacySettings = SettingsStore(defaults: legacyDefaults)
        let legacyProfiles = [
            EQProfile(id: UUID(), name: "Nhạc", gains: Array(repeating: 0, count: 10), preamp: 0),
            EQProfile(id: UUID(), name: "Phim", gains: Array(repeating: 0, count: 10), preamp: 0),
            EQProfile(id: UUID(), name: "Họp", gains: Array(repeating: 0, count: 10), preamp: 0),
        ]
        legacySettings.set(Optional(legacyProfiles), for: EqualizerState.profilesKey)
        legacySettings.set(true, for: EqualizerState.defaultPreampMigratedKey)

        let stateA = EqualizerState(settings: legacySettings)
        #expect(stateA.profiles.count == 4)
        #expect(stateA.profiles.contains { $0.name == "Deep Bass (eqMac)" })

        if let deepBassID = stateA.profiles.first(where: { $0.name == "Deep Bass (eqMac)" })?.id {
            #expect(stateA.canDelete(deepBassID) == false)
            stateA.delete(deepBassID)
            #expect(stateA.profiles.count == 4)
        }

        let customDefaults = makeIsolatedDefaults()
        let customSettings = SettingsStore(defaults: customDefaults)
        let customProfiles = [
            EQProfile(id: UUID(), name: "Studio Custom", gains: Array(repeating: 1.0, count: 10), preamp: 0)
        ]
        customSettings.set(Optional(customProfiles), for: EqualizerState.profilesKey)
        customSettings.set(true, for: EqualizerState.defaultPreampMigratedKey)
        let stateB = EqualizerState(settings: customSettings)
        #expect(stateB.profiles.count == 1)
        #expect(stateB.profiles[0].name == "Studio Custom")

        let emptyDefaults = makeIsolatedDefaults()
        let emptySettings = SettingsStore(defaults: emptyDefaults)
        emptySettings.set(Optional([EQProfile]()), for: EqualizerState.profilesKey)
        emptySettings.set(true, for: EqualizerState.defaultPreampMigratedKey)
        let stateEmpty = EqualizerState(settings: emptySettings)
        #expect(stateEmpty.profiles.isEmpty)
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
        #expect(!added.isSystem)
        #expect(state.canDelete(added.id))
        #expect(state.canRename(added.id))
        #expect(state.profiles.count == 5)
        #expect(state.profiles.last == added)
        #expect(state.selectedID == added.id)
        #expect(launches.launch().selectedID == added.id)
    }

    @Test func addProfileOnAnEmptyListStartsFlat() throws {
        let emptyDefaults = makeIsolatedDefaults()
        let emptySettings = SettingsStore(defaults: emptyDefaults)
        emptySettings.set(Optional([EQProfile]()), for: EqualizerState.profilesKey)
        let state = EqualizerState(settings: emptySettings)
        let added = try #require(state.addProfile(named: "Mới"))
        #expect(added.gains == flat)
        #expect(added.preamp == 0)
        #expect(state.selectedID == added.id)
    }

    @Test func addProfileRejectsABadName() {
        let state = Launches().launch()
        #expect(state.addProfile(named: "   ") == nil)
        #expect(state.addProfile(named: String(repeating: "a", count: 41)) == nil)
        #expect(state.profiles.count == 4)
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
        #expect(fixed.gains == [20, -20, 24, -24, 0, 0, 0, 0, 0, 0])
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
        #expect(state.profiles[0].gains == [24, 1, 0, 0, 0, 0, 0, 0, 0, 0])
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

    @Test func migratesLegacyNegativeDefaultPreampsOnceAndPreservesUserChangesAfterward() {
        let launches = Launches()
        let store = SettingsStore(defaults: launches.defaults)

        // Seed legacy profiles with negative preamps, plus a positive preamp default profile to verify it is NOT overwritten
        let legacyNhac = EQProfile(id: UUID(), name: "Nhạc", gains: [4, 3, 1.5, 0, -1, -1, 0, 1.5, 3, 4], preamp: -4)
        let positivePhim = EQProfile(id: UUID(), name: "Phim", gains: [5, 4, 2, 0, 0, 1.5, 2.5, 2, 1, 0], preamp: 2.5)
        let legacyHop = EQProfile(id: UUID(), name: "Họp", gains: [-6, -4, -2, 0, 1, 2.5, 4, 3.5, 1, 0], preamp: -2)
        let customUser = EQProfile(id: UUID(), name: "CustomBass", gains: [8, 6, 4, 0, 0, 0, 0, 0, 0, 0], preamp: -3)

        store.set(Optional([legacyNhac, positivePhim, legacyHop, customUser]), for: EqualizerState.profilesKey)
        store.set(Optional(legacyNhac.id), for: EqualizerState.selectedKey)

        // First launch: should perform one-time migration of negative default profiles to 0 dB, leaving positive default and custom profile untouched
        let state1 = EqualizerState(settings: store)
        #expect(state1.profiles.first { $0.name == "Nhạc" }?.preamp == 0)
        #expect(state1.profiles.first { $0.name == "Phim" }?.preamp == 2.5)
        #expect(state1.profiles.first { $0.name == "Họp" }?.preamp == 0)
        #expect(state1.profiles.first { $0.name == "CustomBass" }?.preamp == -3)
        #expect(store.value(EqualizerState.defaultPreampMigratedKey) == true)

        // User intentionally lowers "Nhạc" to -2.5 dB
        state1.setPreamp(-2.5)
        #expect(state1.selected?.preamp == -2.5)

        // Subsequent launch: migration must NOT run again and must preserve user's -2.5 dB choice
        let state2 = EqualizerState(settings: store)
        #expect(state2.profiles.first { $0.name == "Nhạc" }?.preamp == -2.5)
        #expect(state2.profiles.first { $0.name == "CustomBass" }?.preamp == -3)
    }

    @Test func duplicateProfileCopiesAndRenames() {
        let state = Launches().launch()
        let sourceID = state.profiles[0].id
        let copy = state.duplicateProfile(sourceID)
        #expect(copy != nil)
        #expect(copy?.name == "Nhạc (Bản sao)")
        #expect(copy?.gains == state.profiles[0].gains)
        #expect(copy?.preamp == state.profiles[0].preamp)
        #expect(state.selectedID == copy?.id)

        // Duplicate again should increment index
        let copy2 = state.duplicateProfile(sourceID)
        #expect(copy2?.name == "Nhạc (2)")
        #expect(state.selectedID == copy2?.id)
    }

    @Test func presetCatalogProtectionRules() {
        let state = Launches().launch()
        let nhacID = state.profiles[0].id
        #expect(state.isSystemDefault(nhacID) == true)
        #expect(state.canDelete(nhacID) == false)
        #expect(state.canRename(nhacID) == false)

        let custom = state.duplicateProfile(nhacID)!
        #expect(state.isSystemDefault(custom.id) == false)
        #expect(state.canDelete(custom.id) == true)
        #expect(state.canRename(custom.id) == true)
    }

    @Test func processingSettingsDefaultsAndPersistence() {
        let launches = Launches()
        let state = launches.launch()
        #expect(state.ceilingDBTP == -0.5)
        #expect(state.loudnessReferenceVolume == 0.60)
        #expect(state.loudnessMaxBassDB == 8.5)
        #expect(state.loudnessMaxTrebleDB == 4.0)

        state.ceilingDBTP = -1.0
        state.loudnessReferenceVolume = 0.75
        state.loudnessMaxBassDB = 10.0
        state.loudnessMaxTrebleDB = 6.0

        let reloaded = launches.launch()
        #expect(reloaded.ceilingDBTP == -1.0)
        #expect(reloaded.loudnessReferenceVolume == 0.75)
        #expect(reloaded.loudnessMaxBassDB == 10.0)
        #expect(reloaded.loudnessMaxTrebleDB == 6.0)
    }

    @Test func resetToDefaultsRestoresPresetsAndSettings() {
        let launches = Launches()
        let state = launches.launch()
        state.ceilingDBTP = 0.0
        state.loudnessReferenceVolume = 0.90
        guard let custom = state.addProfile(named: "Tùy biến") else {
            Issue.record("Failed to create custom profile")
            return
        }
        state.select(custom.id)
        #expect(state.profiles.count == 5)

        state.resetToDefaults()
        // Preserves custom profile and keeps selection
        #expect(state.profiles.count == 5)
        #expect(state.profiles.contains(where: { $0.id == custom.id && $0.name == "Tùy biến" }))
        #expect(state.selectedID == custom.id)
        #expect(state.ceilingDBTP == -0.5)
        #expect(state.loudnessReferenceVolume == 0.60)
    }

    @Test func duplicateProfileHandles40CharNameWithoutInfiniteLoop() {
        let launches = Launches()
        let state = launches.launch()
        let longName = String(repeating: "A", count: 40)
        guard let first = state.addProfile(named: longName) else {
            Issue.record("Failed to create 40-char profile")
            return
        }
        #expect(first.name.count == 40)

        // Duplicating should produce valid copy without infinite loop
        guard let duplicate = state.duplicateProfile(first.id) else {
            Issue.record("Failed to duplicate 40-char profile")
            return
        }
        #expect(duplicate.name != first.name)
        #expect(duplicate.name.count <= 40)
        #expect(duplicate.name.contains("Bản sao"))
    }

    @Test func systemPresetsCannotBeDeletedOrRenamed() {
        let launches = Launches()
        let state = launches.launch()
        for profile in state.profiles where profile.isSystem {
            #expect(state.canDelete(profile.id) == false)
            #expect(state.canRename(profile.id) == false)
            state.delete(profile.id)
            #expect(state.profiles.contains(where: { $0.id == profile.id }))
            state.rename(profile.id, to: "New Name")
            #expect(state.profiles.first(where: { $0.id == profile.id })?.name == profile.name)
        }
    }

    @Test func addFlatProfileCreatesZeroedCustomProfile() {
        let launches = Launches()
        let state = launches.launch()
        guard let flatProfile = state.addFlatProfile(named: "Phẳng Test") else {
            Issue.record("Failed to create flat profile")
            return
        }
        #expect(flatProfile.isSystem == false)
        #expect(flatProfile.preamp == 0.0)
        #expect(flatProfile.gains == Array(repeating: 0.0, count: 10))
        #expect(state.canDelete(flatProfile.id) == true)
        #expect(state.canRename(flatProfile.id) == true)
    }

    @Test func autoHeadroomDefaultsToFalseAndPersists() {
        let store = SettingsStore(defaults: makeIsolatedDefaults())
        let state1 = EqualizerState(settings: store)
        #expect(state1.isAutoHeadroomEnabled == false)

        state1.isAutoHeadroomEnabled = true
        #expect(state1.isAutoHeadroomEnabled == true)

        let state2 = EqualizerState(settings: store)
        #expect(state2.isAutoHeadroomEnabled == true)

        state2.resetToDefaults()
        #expect(state2.isAutoHeadroomEnabled == true, "resetToDefaults must not reset isAutoHeadroomEnabled")
    }
}
