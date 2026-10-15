import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import MyNotchCore
import MyNotchTestSupport

/// A module whose tab asks for a given height.
private final class AskingModule: FeatureModule {
    let descriptor = ModuleDescriptor(id: "asking", displayName: "Asking", systemImage: "circle", defaultEnabled: true, order: 0)
    let height: CGFloat?

    init(height: CGFloat?) { self.height = height }

    func start(_ context: ModuleContext) async throws(ModuleError) {}
    func stop() async {}

    func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id, title: "Asking", systemImage: "star", preferredHeight: height, acceptsKeyboard: true,
            dropTypes: [.plainText], onDrop: { _ in true }, content: AnyView(EmptyView())
        )
    }

    func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? { nil }
}

/// The open notch has at most `NotchTab.heightRange.upperBound` for a tab, so a tab that asks for more is cut there. The
/// registry, which every running module's tab passes through, tells the log (a fault naming the module) and holds the tab
/// to that height, so the mistake is found in a module's own tests and never stops the app.
@Suite struct TabHeightGuardTests {
    @Test func aTabThatAsksForTheMostItMayRunsAsItIsAndIsNotReported() async {
        let harness = Harness([AskingModule(height: NotchTab.heightRange.upperBound)])
        await harness.registry.bootstrap()
        #expect(harness.registry.tabs.map(\.preferredHeight) == [NotchTab.heightRange.upperBound])
        #expect(harness.oversizedTabs.reports.isEmpty)
    }

    @Test func aTabWithNoAskAndOneBelowTheRangeAreNotReported() async {
        for height in [nil, 50, 190] as [CGFloat?] {
            let harness = Harness([AskingModule(height: height)])
            await harness.registry.bootstrap()
            #expect(harness.registry.tabs.map(\.preferredHeight) == [height])
            #expect(harness.oversizedTabs.reports.isEmpty)
        }
    }

    @Test func aTabThatAsksForMoreIsReportedWithItsModuleAndHeldToTheLimit() async {
        let harness = Harness([AskingModule(height: 300)])
        await harness.registry.bootstrap()
        #expect(harness.oversizedTabs.reports == [.init(module: "asking", asked: 300)])
        let tab = harness.registry.tabs.first
        #expect(tab?.preferredHeight == NotchTab.heightRange.upperBound)
        #expect(tab?.asksTooMuch == false)
        #expect(harness.registry.state(of: "asking") == .running)
    }

    @Test func theHeldTabIsTheSameTabInEveryOtherWay() async throws {
        let harness = Harness([AskingModule(height: 500)])
        await harness.registry.bootstrap()
        let tab = try #require(harness.registry.tabs.first)
        #expect(tab.id == "asking")
        #expect(tab.title == "Asking")
        #expect(tab.systemImage == "star")
        #expect(tab.acceptsKeyboard)
        #expect(tab.dropTypes == [.plainText])
        #expect(tab.onDrop?([]) == true)
    }

    @Test func eachOversizedTabIsReportedOnceForEachTimeItStarts() async {
        let harness = Harness([AskingModule(height: 241)])
        await harness.registry.bootstrap()
        await harness.registry.retry("asking")
        #expect(harness.oversizedTabs.reports == [.init(module: "asking", asked: 241), .init(module: "asking", asked: 241)])
    }

    /// The reaction nobody injects is a log line: the app and a user's Debug build must never stop on it.
    @Test func withoutAnInjectedReactionAnOversizedTabStillRunsHeldToTheLimit() async {
        let harness = Harness([])
        let registry = ModuleRegistry(
            modules: [AskingModule(height: 300)], settings: harness.settings, activities: harness.activities,
            lockScreen: harness.lockScreen, permissions: harness.permissions, hotkeys: harness.hotkeys, presenter: harness.presenter,
            scheduler: harness.scheduler, storageRoot: harness.storageRoot, services: harness.services
        )
        await registry.bootstrap()
        #expect(registry.tabs.map(\.preferredHeight) == [NotchTab.heightRange.upperBound])
        // The reaction itself, called straight: a log line and nothing else.
        ModuleRegistry.reportOversizedTab("asking", 300)
    }
}
