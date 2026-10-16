import AppKit
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import PetModule

/// The module in a registry of its own, with the activity center it is given: other modules' activities are put into it by the test.
@MainActor final class PetHarness {
    let settings = SettingsStore(defaults: makeIsolatedDefaults())
    let scheduler = ManualScheduler()
    let activities: ActivityCenter
    let registry: ModuleRegistry
    let module: PetModule
    let rig: StageRig
    /// The stage the module made.
    private(set) var stage: CatStage?

    static let someone: ModuleID = "media"
    static let someoneElse: ModuleID = "todo"

    init() {
        let scheduler = scheduler
        activities = ActivityCenter(scheduler: scheduler)
        let rig = StageRig()
        self.rig = rig
        let box = StageBox()
        module = PetModule(activities: activities, makeStage: { moduleScheduler in
            let stage = CatStage(scheduler: moduleScheduler, sources: rig.sources)
            box.stage = stage
            return stage
        })
        registry = ModuleRegistry(
            modules: [module], settings: settings, activities: activities, lockScreen: LockScreenContentCenter(),
            permissions: FakePermissionCenter(), hotkeys: HotkeyRegistry(backend: FakeHotkeyBackend()), presenter: FakePresenter(),
            scheduler: scheduler,
            storageRoot: {
                let base = ScratchFolders.shared.reserve()
                return StorageRoot(applicationSupport: base.appending(path: "ApplicationSupport"), caches: base.appending(path: "Caches"))
            }(),
            services: ServiceRegistry(scheduler: scheduler)
        )
        self.box = box
    }

    private let box: StageBox?

    final class StageBox { var stage: CatStage? }

    var madeStage: CatStage? { box?.stage }

    func start() async { await registry.bootstrap() }

    var entries: [ActivityCenter.Entry] { activities.entries }
    var cat: ActivityCenter.Entry? { entries.first { $0.module == "pet" } }

    func advance(_ seconds: Double) { scheduler.advance(by: .milliseconds(Int((seconds * 1000).rounded()))) }

    /// What the observers of the activity center and of the settings do on their next turn.
    func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    func settle() async { for _ in 0..<30 { await Task.yield() } }

    func put(_ id: String, from module: ModuleID = PetHarness.someone, priority: ActivityPriority = .normal, expiresAfter: Duration? = nil) {
        activities.set(
            LiveActivity(id: id, priority: priority, expiresAfter: expiresAfter, leading: AnyView(Color.clear), trailing: AnyView(Color.clear)),
            from: module
        )
    }

    func setting<Value>(_ name: String, _ value: Value) where Value: Codable & Sendable {
        settings.set(value, for: SettingKey("module.pet.\(name)", default: value))
    }
}

@Suite(.serialized) @MainActor struct PetModuleTests {
    @Test func describesItself() {
        let descriptor = PetModule(activities: ActivityCenter(scheduler: ManualScheduler())).descriptor
        #expect(descriptor.id == "pet")
        #expect(descriptor.displayName == "Mèo")
        #expect(descriptor.systemImage == "cat")
        #expect(descriptor.defaultEnabled)
        #expect(descriptor.order == 960)
        #expect(descriptor.permissions.isEmpty && descriptor.optionalPermissions.isEmpty)
    }

    @Test func hasNoTabSoTheTabBarIsNoLonger() async {
        let harness = PetHarness()
        await harness.start()
        #expect(PetModule(activities: harness.activities).makeTab() == nil)
        #expect(harness.registry.tabs.isEmpty)
    }

    // MARK: Coming out

    @Test func theCatComesOutOnAFreeNotchAfterAPauseAndNotAtOnce() async {
        let harness = PetHarness()
        await harness.start()
        #expect(harness.cat == nil, "not at the moment the app starts: whatever is published as it launches gets there first")
        harness.advance(1.4)
        #expect(harness.cat == nil)
        harness.advance(0.2)
        #expect(harness.cat != nil)
        #expect(harness.module.isShowing)
        #expect(harness.activities.current?.module == "pet")
    }

    @Test func itIsAtTheLowestPriorityThereIsAndAsksForNoStrip() async throws {
        let harness = PetHarness()
        await harness.start()
        harness.advance(2)
        let activity = try #require(harness.cat).activity
        #expect(activity.priority == .low)
        #expect(activity.bottom == nil)
        #expect(activity.bottomHeight == 0)
        #expect(!activity.hasBottom, "so the notch grows downward by nothing")
        #expect(activity.expiresAfter == nil)
        #expect(activity.id == "cat")
        #expect(activity.summary != nil)
        #expect(activity.minimal != nil)
    }

    @Test func itNeverComesOutWhileAnotherModuleHasAnActivityAndComesBackAfterThePauseWhenItsGone() async {
        let harness = PetHarness()
        harness.put("playing")
        await harness.start()
        harness.advance(30)
        #expect(harness.cat == nil)
        harness.activities.clear(id: "playing", from: PetHarness.someone)
        await harness.settle()
        harness.advance(1.4)
        #expect(harness.cat == nil)
        harness.advance(0.2)
        #expect(harness.cat != nil)
    }

    @Test func itStepsAsideAtOnceWhenAnActivityAppearsAndIsNeverABubbleNorARow() async {
        let harness = PetHarness()
        await harness.start()
        harness.advance(2)
        #expect(harness.cat != nil)

        harness.put("playing", priority: .normal)
        await harness.settle(until: { harness.cat == nil })
        #expect(harness.cat == nil, "gone without any time passing")
        #expect(!harness.module.isShowing)
        #expect(harness.activities.current?.module == PetHarness.someone)
        #expect(harness.activities.others.isEmpty, "no bubble")
        #expect(harness.activities.ordered.count == 1, "no row in the list")
        #expect(harness.activities.hiddenCount == 0, "and no +N")
    }

    @Test func itStepsAsideForAnActivityOfItsOwnPriorityToo() async {
        // The to-do count, an agent at work and the performance strip are low as well, and among equals the one that came first keeps the
        // notch: which would be the cat.
        let harness = PetHarness()
        await harness.start()
        harness.advance(2)
        harness.put("todo", from: PetHarness.someoneElse, priority: .low)
        await harness.settle(until: { harness.cat == nil })
        #expect(harness.cat == nil)
        #expect(harness.activities.current?.module == PetHarness.someoneElse)
        #expect(harness.activities.others.isEmpty)
    }

    @Test func aNoticeThatComesAndGoesTakesTheNotchAndTheCatReturnsAPauseAfterIt() async {
        let harness = PetHarness()
        await harness.start()
        harness.advance(2)
        harness.put("charging", priority: .normal, expiresAfter: .seconds(4))
        await harness.settle(until: { harness.cat == nil })
        #expect(harness.cat == nil)
        harness.advance(3.9)
        #expect(harness.cat == nil)
        harness.advance(0.2)
        await harness.settle(until: { !harness.pendingShowIsEmpty })
        harness.advance(1.4)
        #expect(harness.cat == nil, "the pause is still on")
        harness.advance(0.2)
        #expect(harness.cat != nil)
    }

    @Test func aNotchThatFlickersBetweenActivitiesNeverGetsACatInTheGaps() async {
        let harness = PetHarness()
        await harness.start()
        harness.advance(2)
        for _ in 0..<10 {
            harness.put("a")
            await harness.settle()
            #expect(harness.cat == nil)
            harness.advance(0.6)
            harness.activities.clear(id: "a", from: PetHarness.someone)
            await harness.settle()
            harness.advance(0.6)
            #expect(harness.cat == nil, "a pause of 0.6 s is not a free notch")
        }
        harness.advance(1)
        #expect(harness.cat != nil)
    }

    @Test func theCatAloneInThePanelOfOneActivityOnlyIsNotOthersOfItself() async {
        let harness = PetHarness()
        await harness.start()
        harness.advance(2)
        #expect(harness.activities.entries.count == 1)
        #expect(harness.activities.others.isEmpty)
        // Its own publishing does not make it step aside for itself.
        harness.advance(60)
        #expect(harness.cat != nil)
    }

    // MARK: Settings

    @Test func theSettingsHaveTheirDefaults() throws {
        let harness = RegistryHarness([PetModule(activities: ActivityCenter(scheduler: ManualScheduler()))])
        let settings = try #require(harness.settingsEnvironment(for: "pet")).settings
        let keys = PetSettingsKeys(settings)
        #expect(settings.value(keys.show))
        #expect(!settings.value(keys.bothWings))
        #expect(!settings.value(keys.meow))
        #expect(settings.value(keys.sleepMinutes) == 5)
        #expect(keys.show.name == "module.pet.show")
    }

    @Test func theSettingsRowsAreThereWhetherOrNotTheModuleRuns() throws {
        let harness = RegistryHarness([PetModule(activities: ActivityCenter(scheduler: ManualScheduler()))])
        #expect(harness.registry.settingsView(for: "pet") != nil)
    }

    @Test func turningTheCatOffTakesItOffTheNotchAndOnBringsItBackAfterThePause() async {
        let harness = PetHarness()
        await harness.start()
        harness.advance(2)
        #expect(harness.cat != nil)
        harness.setting("show", false)
        await harness.settle(until: { harness.cat == nil })
        #expect(harness.cat == nil)
        harness.advance(60)
        #expect(harness.cat == nil)
        harness.setting("show", true)
        await harness.settle(until: { !harness.pendingShowIsEmpty })
        harness.advance(2)
        #expect(harness.cat != nil)
    }

    @Test func theChoicesReachTheCat() async throws {
        let harness = PetHarness()
        await harness.start()
        let stage = try #require(harness.madeStage)
        #expect(stage.tuning.sleepAfter == 300)
        #expect(!stage.bothWings)
        #expect(!stage.playsMeow)
        harness.setting("sleepMinutes", 10)
        harness.setting("bothWings", true)
        harness.setting("meow", true)
        await harness.settle(until: { stage.playsMeow })
        #expect(stage.tuning.sleepAfter == 600)
        #expect(stage.bothWings)
        #expect(stage.playsMeow)
        harness.setting("sleepMinutes", 2)
        await harness.settle(until: { stage.tuning.sleepAfter == 120 })
        #expect(stage.tuning.sleepAfter == 120)
    }

    // MARK: Stopping

    @Test func stoppingTheModuleTakesTheCatOffAndAnythingOfItsStillPendingWithIt() async {
        let harness = PetHarness()
        await harness.start()
        harness.advance(0.5)
        await harness.registry.setEnabled(false, for: "pet")
        harness.advance(10)
        #expect(harness.cat == nil, "the pause it was waiting out did not bring it out")
        #expect(harness.scheduler.pendingCount == 0)

        await harness.registry.setEnabled(true, for: "pet")
        harness.advance(2)
        #expect(harness.cat != nil)
        await harness.registry.setEnabled(false, for: "pet")
        #expect(harness.cat == nil)
        #expect(!harness.module.isShowing)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func aStoppedModuleLeavesNoLifeInTheCatsStage() async throws {
        let harness = PetHarness()
        await harness.start()
        harness.advance(2)
        let stage = try #require(harness.madeStage)
        await harness.registry.setEnabled(false, for: "pet")
        #expect(!stage.isAlive)
        #expect(!stage.isTicking)
    }

    @Test func theViewsOfTheCatAsTheNotchBuildsThemAskForNothing() async throws {
        let harness = PetHarness()
        await harness.start()
        harness.advance(2)
        let activity = try #require(harness.cat).activity
        let stage = try #require(harness.madeStage)
        let counter = CatSpriteViewTests.Counter()
        let view = HStack(spacing: 0) {
            activity.leading.frame(width: 64)
            Spacer(minLength: 185)
            activity.trailing.frame(width: 64)
        }
        .frame(width: 313, height: 32)
        .onNotchStripWidth { counter.stripWidths.append($0) }
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 313, height: 32), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        #expect(stage.attachedHosts.count == 2, "both wings have a cat view in them")
        #expect(counter.stripWidths.allSatisfy { $0 == 0 })
        #expect(hosting.fittingSize == CGSize(width: 313, height: 32))
        window.contentView = nil
        #expect(!stage.isAlive)
    }
}

extension PetHarness {
    var pendingShowIsEmpty: Bool { scheduler.pendingCount == 0 }
}
