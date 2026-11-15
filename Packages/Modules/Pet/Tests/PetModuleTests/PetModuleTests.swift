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
    /// Which display each window the test puts a notch in is on, and where the module hears of the screens changing.
    let displayMap = DisplayMap()
    let screenNotifications = NotificationCenter()
    /// The displays that are connected, as the settings and the module are told; none unless a test says.
    let connected = ConnectedBox()

    final class ConnectedBox { var displays: [ConnectedDisplay] = [] }

    static let someone: ModuleID = "media"
    static let someoneElse: ModuleID = "todo"

    init() {
        let scheduler = scheduler
        activities = ActivityCenter(scheduler: scheduler)
        let rig = StageRig()
        self.rig = rig
        let box = StageBox()
        let (displayMap, screenNotifications, connected) = (displayMap, screenNotifications, connected)
        module = PetModule(activities: activities, makeStages: { moduleScheduler in
            // A stage for each display, reading what the rig holds.
            let stages = CatStages(
                makeStage: { _ in CatStage(scheduler: moduleScheduler, sources: rig.sources) },
                displayOf: { displayMap.displayOf($0) }, notifications: screenNotifications
            )
            box.stages = stages
            return stages
        }, displays: Displays(current: { connected.displays }, notifications: screenNotifications))
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

    final class StageBox { var stages: CatStages? }

    /// The stages the module made.
    var madeStages: CatStages? { box?.stages }

    /// A notch on `display`, in a window that is never shown, with the pets of the module's stages in it.
    func notch(_ geometry: NotchGeometry, on display: DisplayID) throws -> (window: NSWindow, container: CatBodyContainer) {
        let stages = try #require(madeStages)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 38), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        displayMap.put(window, on: display)
        let container = CatBodyContainer(stages: stages)
        container.frame = window.contentLayoutRect
        window.contentView?.addSubview(container)
        container.configure(geometry: geometry)
        container.layoutSubtreeIfNeeded()
        return (window, container)
    }

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
        #expect(descriptor.displayName == "Thú cưng")
        #expect(descriptor.systemImage == "pawprint")
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

    @Test func itIsAtTheLowestPriorityThereIsAndPlaysInTheTopRowOfTheNotchWithNoStripUnderIt() async throws {
        let harness = PetHarness()
        await harness.start()
        harness.advance(2)
        let activity = try #require(harness.cat).activity
        #expect(activity.priority == .low)
        #expect(activity.hasBody, "the cat is drawn across the top row of the notch")
        #expect(activity.bottom == nil && activity.bottomHeight == 0 && !activity.hasBottom, "and the notch does not grow downward for it")
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
        #expect(settings.value(keys.coat) == .tabby)
        #expect(!settings.value(keys.meow))
        #expect(settings.value(keys.sleepMinutes) == 5)
        #expect(settings.value(keys.busyReaction) == .occasionally)
        #expect(settings.value(keys.playPlace) == .portal)
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

    @Test func theChoicesReachThePetsOnEveryScreenWhetherItIsThereYetOrComesLater() async throws {
        let harness = PetHarness()
        await harness.start()
        let stages = try #require(harness.madeStages)
        let mac = try harness.notch(Screens.hardware, on: Screens.macID)
        #expect(stages.all.count == 1)
        for stage in stages.all {
            #expect(stage.tuning.sleepAfter == 300)
            #expect(stage.coat == .tabby)
            #expect(!stage.playsMeow)
        }
        harness.setting("sleepMinutes", 10)
        harness.setting("coat", CatCoat.tuxedo)
        harness.setting("meow", true)
        await harness.settle(until: { stages.all.allSatisfy(\.playsMeow) })
        #expect(stages.tuning.sleepAfter == 600 && stages.coat == .tuxedo && stages.playsMeow)
        // A screen that comes later has them too.
        let pill = try harness.notch(Screens.pill, on: Screens.externalID)
        #expect(stages.all.count == 2)
        for stage in stages.all {
            #expect(stage.tuning.sleepAfter == 600)
            #expect(stage.coat == .tuxedo)
            #expect(stage.playsMeow)
        }
        harness.setting("sleepMinutes", 2)
        await harness.settle(until: { stages.all.allSatisfy { $0.tuning.sleepAfter == 120 } })
        for stage in stages.all { #expect(stage.tuning.sleepAfter == 120) }
        withExtendedLifetime((mac, pill)) {}
    }

    @Test func changingWhereTheCatPlaysPutsItThereAtOnceWithoutTakingItOffTheNotch() async throws {
        let harness = PetHarness()
        await harness.start()
        harness.advance(2)
        let before = try #require(harness.cat).activity
        #expect(before.hasBody && !before.hasBottom, "beside the camera, in the top row")
        harness.setting("playPlace", PlayPlace.strip)
        await harness.settle(until: { harness.cat?.activity.hasBottom == true })
        let strip = try #require(harness.cat).activity
        #expect(strip.hasBottom && strip.bottomHeight == 26 && strip.bottomScope == .hardwareNotchOnly && strip.hasBody)
        #expect(harness.entries.count == 1 && harness.cat?.id == "pet/cat", "the same activity, in its new place")
        #expect(harness.module.isShowing && harness.pendingShowIsEmpty, "it was not taken off and brought back")
        harness.setting("playPlace", PlayPlace.portal)
        await harness.settle(until: { harness.cat?.activity.hasBottom == false })
        #expect(harness.cat?.activity.hasBottom == false && harness.cat?.activity.hasBody == true)
        #expect(harness.module.isShowing)
    }

    @Test func theBusyReactionReachesEveryPetTheMomentItIsChanged() async throws {
        let harness = PetHarness()
        await harness.start()
        let stages = try #require(harness.madeStages)
        let notches = [try harness.notch(Screens.hardware, on: Screens.macID), try harness.notch(Screens.pill, on: Screens.externalID)]
        #expect(stages.all.count == 2)
        for stage in stages.all { #expect(stage.tuning.reactsToBusyMachine, "Thỉnh thoảng") }
        harness.setting("busyReaction", BusyReaction.off)
        await harness.settle(until: { stages.all.allSatisfy { !$0.tuning.reactsToBusyMachine } })
        for stage in stages.all { #expect(!stage.tuning.reactsToBusyMachine, "Tắt, with nothing else changed") }
        harness.setting("busyReaction", BusyReaction.occasionally)
        await harness.settle(until: { stages.all.allSatisfy(\.tuning.reactsToBusyMachine) })
        for stage in stages.all { #expect(stage.tuning.reactsToBusyMachine) }
        withExtendedLifetime(notches) {}
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

    @Test func aStoppedModuleLeavesNoLifeInAnyScreensStage() async throws {
        let harness = PetHarness()
        await harness.start()
        harness.advance(2)
        let stages = try #require(harness.madeStages)
        // A pet is on a notch of each display, as it is with a Mac and a pill on the desk.
        let notches = [try harness.notch(Screens.hardware, on: Screens.macID), try harness.notch(Screens.pill, on: Screens.externalID)]
        let live = stages.all
        #expect(live.count == 2)
        for stage in live { #expect(stage.isAlive && stage.isTicking) }
        await harness.registry.setEnabled(false, for: "pet")
        for stage in live {
            #expect(!stage.isAlive)
            #expect(!stage.isTicking)
        }
        #expect(stages.all.isEmpty && harness.scheduler.pendingCount == 0)
        withExtendedLifetime(notches) {}
    }

    @Test func withTheStripChosenTheStripIsForTheScreensWithAHardwareNotchOnlyAndTheBodyIsStillThere() async throws {
        let harness = PetHarness()
        harness.setting("playPlace", PlayPlace.strip)
        await harness.start()
        harness.advance(2)
        let activity = try #require(harness.cat).activity
        #expect(activity.bottom != nil && activity.bottomHeight == 26 && activity.hasBottom)
        #expect(activity.bottomScope == .hardwareNotchOnly, "a virtual notch, which has room in its body, keeps the cat there")
        #expect(activity.hasBody)
    }

    @Test func theStripAsTheNotchBuildsItAsksForNothingAndTheWingsAreEmpty() async throws {
        let harness = PetHarness()
        harness.setting("playPlace", PlayPlace.strip)
        await harness.start()
        harness.advance(2)
        let activity = try #require(harness.cat).activity
        let stages = try #require(harness.madeStages)
        let counter = CatSpriteViewTests.Counter()
        // As the notch lays the activity out: the wings, and the strip under them as wide as the notch.
        let view = VStack(spacing: 0) {
            HStack(spacing: 0) {
                activity.leading.frame(width: 64)
                Spacer(minLength: 185)
                activity.trailing.frame(width: 64)
            }
            .frame(height: 32)
            activity.bottom.map { $0.frame(height: activity.bottomHeight) }
        }
        .frame(width: 300)
        .onNotchStripWidth { counter.stripWidths.append($0) }
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 58), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let stage = try #require(stages.all.first)
        #expect(stages.all.count == 1 && stage.attachedHosts.count == 1, "one cat view, in the strip")
        #expect(counter.stripWidths.allSatisfy { $0 == 0 })
        #expect(hosting.fittingSize == CGSize(width: 300, height: 58))
        let cat = try #require(stage.attachedHosts.first)
        #expect(cat.convert(cat.bounds, to: hosting).height == 26)
        #expect(cat.convert(cat.bounds, to: hosting).width == 300)
        window.contentView = nil
        #expect(!stage.isAlive)
    }
}

extension PetHarness {
    var pendingShowIsEmpty: Bool { scheduler.pendingCount == 0 }
}
