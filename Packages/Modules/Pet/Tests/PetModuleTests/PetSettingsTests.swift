import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import PetModule

@Suite @MainActor struct PetSettingsTests {
    func environment() throws -> ModuleSettings {
        let harness = RegistryHarness([PetModule(activities: ActivityCenter(scheduler: ManualScheduler()))])
        return try #require(harness.settingsEnvironment(for: "pet")).settings
    }

    @Test func theCatIsOnByDefaultAndTheRestIsOff() throws {
        let settings = try environment()
        let keys = PetSettingsKeys(settings)
        #expect(settings.value(keys.show), "Hiện mèo trên notch")
        #expect(settings.value(keys.coat) == .tabby, "Màu mèo")
        #expect(!settings.value(keys.meow), "Tiếng mèo khi bấm")
    }

    @Test func theCoatIsKeptByNameAndAnUnknownOneReadsAsTheDefault() throws {
        let settings = try environment()
        let keys = PetSettingsKeys(settings)
        for coat in CatCoat.allCases {
            settings.set(coat, for: keys.coat)
            #expect(settings.value(keys.coat) == coat)
        }
        #expect(CatCoat(rawValue: "tabby") == .tabby && CatCoat(rawValue: "tuxedo") == .tuxedo && CatCoat(rawValue: "grey") == .grey)
    }

    @Test func theChoicesAreKeptUnderTheModulesOwnNames() throws {
        let keys = PetSettingsKeys(try environment())
        #expect([keys.show.name, keys.coat.name, keys.meow.name, keys.sleepMinutes.name] == [
            "module.pet.show", "module.pet.coat", "module.pet.meow", "module.pet.sleepMinutes",
        ])
    }

    @Test func theCatSleepsAfterTwoFiveOrTenMinutesAndFiveByDefault() throws {
        #expect(PetSettingsKeys.sleepOptions == [2, 5, 10])
        let settings = try environment()
        let keys = PetSettingsKeys(settings)
        #expect(keys.tuning(settings).sleepAfter == 300)
        for minutes in PetSettingsKeys.sleepOptions {
            settings.set(minutes, for: keys.sleepMinutes)
            #expect(keys.tuning(settings).sleepAfter == Double(minutes) * 60)
        }
    }

    @Test func aStoredTimeThatIsNotOneOfTheThreeMeansTheNearestOne() {
        let expected = [0: 2, 1: 2, 2: 2, 3: 2, 4: 5, 5: 5, 6: 5, 7: 5, 8: 10, 10: 10, 99: 10, -5: 2]
        for (stored, snapped) in expected { #expect(PetSettingsKeys.snapped(sleepMinutes: stored) == snapped, "\(stored)") }
    }

    @Test func theRowsBuildAndTakeTheSpaceTheFormGivesThem() throws {
        let settings = try environment()
        let view = Form { PetSettingsView(keys: PetSettingsKeys(settings), settings: settings) }.frame(width: 480, height: 400)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 480, height: 400)
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.fittingSize.width > 0)
    }
}

@Suite struct CatTypesTests {
    @Test func theGeneratorGivesTheNumbersItsMakersPublishedForASeedOfZero() {
        var generator = SplitMix64(seed: 0)
        #expect(generator.next() == 0xE220_A839_7B1D_CDAF)
        #expect(generator.next() == 0x6E78_9E6A_A1B9_65F4)
        #expect(generator.next() == 0x06C4_5D18_8009_454F)
    }

    @Test func aSeedIsAStreamOfItsOwn() {
        var one = SplitMix64(seed: 1)
        var other = SplitMix64(seed: 1)
        var different = SplitMix64(seed: 2)
        let first = (0..<8).map { _ in one.next() }
        #expect(first == (0..<8).map { _ in other.next() })
        #expect(first != (0..<8).map { _ in different.next() })
    }

    @Test func aPlanThatOnlyLastsLongerLooksTheSameWhenTheCatStandsStillButNotWhenItWalks() {
        let sit = CatPlan(move: .sit, facing: .left, from: 0.5, to: 0.5, began: 0, duration: 3)
        var longer = sit
        longer.duration = 9
        longer.began = 40
        #expect(sit.looksLike(longer))
        let walk = CatPlan(move: .walk, facing: .right, from: 0.1, to: 0.4, began: 0, duration: 3)
        var slower = walk
        slower.duration = 6
        #expect(!walk.looksLike(slower))
        var turned = sit
        turned.facing = .right
        #expect(!sit.looksLike(turned))
        var harder = CatPlan(move: .frantic, facing: .right, from: 0, to: 1, began: 0, duration: 2)
        let calm = harder
        harder.fpsScale = 1.4
        #expect(!calm.looksLike(harder))
    }
}

/// The real things the cat reads, once each: they read the machine and change nothing.
@Suite @MainActor struct RealSensesTests {
    @Test func theProcessorLoadIsNothingTheFirstTimeAndAShareOfOneAfter() async throws {
        let sensor = HostCPULoad()
        #expect(sensor.load() == nil, "a first read has nothing to compare with")
        // Some work for the counters to count.
        var sum = 0.0
        for index in 0..<2_000_000 { sum += Double(index).squareRoot() }
        #expect(sum > 0)
        try await Task.sleep(for: .milliseconds(150))
        let load = try #require(sensor.load())
        #expect((0.0...1.0).contains(load))
    }

    @Test func theIdleTimeIsSomeNumberOfSecondsAndNeverNegative() {
        let idle = SystemIdleTime().secondsSinceLastInput()
        #expect(idle >= 0)
        #expect(idle.isFinite)
    }

    @Test func theAudioProbeAnswersWithoutTouchingAnything() {
        // Whatever the machine is doing, it is a yes or a no; this is that the read does not crash, and does so twice in a row.
        _ = AudioOutputProbe().isPlaying()
        _ = AudioOutputProbe().isPlaying()
    }

    @Test func thePointerIsSomewhereOnTheScreens() {
        let point = SystemPointer().location()
        #expect(point.x.isFinite && point.y.isFinite)
    }
}
