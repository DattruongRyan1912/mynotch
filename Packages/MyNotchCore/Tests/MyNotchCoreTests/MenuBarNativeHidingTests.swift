import CoreGraphics
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

/// Stands in for macOS 27's restriction of the menu bar: records what it was asked, and takes it when told to.
final class FakeRestriction: MenuBarRestrictionProvider {
    var takes = true
    /// Holds the completions instead of calling them, for a test that answers them late.
    var deferred = false
    private(set) var allowed: [String]?
    private(set) var log: [String] = []
    private var waiting: [(Bool) -> Void] = []

    func restrict(toApps allowed: [String], completion: @escaping @MainActor (Bool) -> Void) {
        log.append("restrict")
        self.allowed = allowed
        if deferred { waiting.append(completion) } else { completion(takes) }
    }

    func lift() {
        log.append("lift")
        allowed = nil
    }

    func answer() {
        let all = waiting
        waiting = []
        all.forEach { $0(takes) }
    }
}

@Suite struct MenuBarNativeHidingTests {
    private static let screen = MenuBarScreen(frame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117), barHeight: 38)
    /// ‹‹ at 1 300, ‹ at 1 400, the MyNotch icon right of it.
    private static let layout = MenuBarLayout(
        screens: [screen], hiddenSeparator: CGRect(x: 1_400, y: 1_093, width: 16, height: 24),
        alwaysHiddenSeparator: CGRect(x: 1_300, y: 1_093, width: 16, height: 24)
    )

    private static func item(_ app: String, x: CGFloat, position: Int = 0) -> MenuBarItem {
        MenuBarItem(
            id: "\(app):\(position)", pid: 1, ownerBundleID: "com.example.\(app)", ownerName: app, title: nil, details: nil,
            frame: CGRect(x: x, y: 1_093, width: 24, height: 24), order: 0
        )
    }

    private final class Rig {
        let provider = FakeRestriction()
        let source = FakeItemSource()
        var running = ["com.example.always", "com.example.hidden", "com.example.shown", "com.apple.finder", "io.mynotch"]
        var layout = MenuBarNativeHidingTests.layout
        private(set) var hiding: MenuBarNativeHiding!
        var failures = 0
        var changes = 0

        init() {
            source.listed = [
                MenuBarNativeHidingTests.item("always", x: 1_200), MenuBarNativeHidingTests.item("hidden", x: 1_350),
                MenuBarNativeHidingTests.item("shown", x: 1_500),
            ]
            hiding = MenuBarNativeHiding(
                provider: provider, source: source, runningApps: { [unowned self] in running }, ownBundleID: "io.mynotch"
            )
            hiding.onFailed = { [unowned self] in failures += 1 }
            hiding.onChanged = { [unowned self] in changes += 1 }
        }

        func apply(_ level: MenuBarHider.Level) async {
            hiding.apply(level) { [unowned self] in layout }
            await hiding.settled()
        }
    }

    @Test func collapsedKeepsEveryAppButTheHiddenSectionsOnTheBarWithMyNotchAndApple() async {
        let rig = Rig()
        await rig.apply(.collapsed)
        #expect(rig.provider.allowed == ["com.apple.finder", "com.example.shown", "io.mynotch"])
        #expect(rig.hiding.isRestricted)
        #expect(rig.hiding.hiddenApps == ["com.example.always": .alwaysHidden, "com.example.hidden": .hidden])
        #expect(rig.changes == 1)
    }

    @Test func expandedHidesOnlyTheAlwaysHiddenSection() async {
        let rig = Rig()
        await rig.apply(.expanded)
        #expect(rig.provider.allowed == ["com.apple.finder", "com.example.hidden", "com.example.shown", "io.mynotch"])
        #expect(rig.hiding.hiddenApps == ["com.example.always": .alwaysHidden])
    }

    @Test func allGivesEverythingBackAtOnce() async {
        let rig = Rig()
        await rig.apply(.collapsed)
        rig.hiding.apply(.all) { MenuBarNativeHidingTests.layout }
        // No read and no wait.
        #expect(rig.provider.log == ["restrict", "lift"])
        #expect(!rig.hiding.isRestricted)
        #expect(rig.hiding.hiddenApps.isEmpty)
        #expect(rig.changes == 2)
    }

    @Test func anAppWithItemsInTwoSectionsGoesWithTheMoreVisible() async {
        let rig = Rig()
        rig.source.listed.append(Self.item("hidden", x: 1_600, position: 1))
        await rig.apply(.collapsed)
        #expect(rig.hiding.hiddenApps["com.example.hidden"] == nil)
        #expect(rig.provider.allowed?.contains("com.example.hidden") == true)
    }

    @Test func anAppHiddenNowKeepsTheSectionItWasReadInSinceItsFramesSayWhereItWas() async {
        let rig = Rig()
        await rig.apply(.expanded)
        // The always-hidden app is away; the system leaves its frame among the shown ones.
        rig.source.listed[0] = Self.item("always", x: 1_500)
        await rig.apply(.collapsed)
        #expect(rig.hiding.hiddenApps["com.example.always"] == .alwaysHidden)
    }

    @Test func anAppTheUserDraggedWhileItShowedIsReadAgain() async {
        let rig = Rig()
        await rig.apply(.expanded)
        // Shown at .expanded and dragged right of ‹.
        rig.source.listed[1] = Self.item("hidden", x: 1_600)
        await rig.apply(.collapsed)
        #expect(rig.hiding.hiddenApps["com.example.hidden"] == nil)
    }

    @Test func myNotchAndAppsThatAreNotRunningAreNeverOnTheHiddenList() async {
        let rig = Rig()
        rig.running.removeAll { $0 == "com.example.always" }
        rig.source.listed.append(MenuBarItem(
            id: "own", pid: 2, ownerBundleID: "io.mynotch", ownerName: "MyNotch", title: nil, details: nil,
            frame: CGRect(x: 1_250, y: 1_093, width: 24, height: 24), order: 0
        ))
        await rig.apply(.collapsed)
        #expect(rig.hiding.hiddenApps == ["com.example.hidden": .hidden])
        #expect(rig.provider.allowed?.contains("io.mynotch") == true)
    }

    @Test func withNothingInAHiddenSectionNothingIsRestricted() async {
        let rig = Rig()
        rig.source.listed = [Self.item("shown", x: 1_500)]
        await rig.apply(.collapsed)
        #expect(rig.provider.log == ["lift"])
        #expect(!rig.hiding.isRestricted)
    }

    @Test func aRestrictionThatDoesNotTakeIsLiftedAndReported() async {
        let rig = Rig()
        rig.provider.takes = false
        await rig.apply(.collapsed)
        #expect(rig.failures == 1)
        #expect(!rig.hiding.isRestricted)
        #expect(rig.provider.log == ["restrict", "lift"])
    }

    @Test func aRestrictionOvertakenBeforeItTookIsNotTakenForTheCurrentOne() async {
        let rig = Rig()
        rig.provider.deferred = true
        await rig.apply(.collapsed)
        rig.hiding.apply(.all) { MenuBarNativeHidingTests.layout }
        rig.provider.answer()
        #expect(!rig.hiding.isRestricted)
        #expect(rig.hiding.hiddenApps.isEmpty)
    }

    @Test func suspendingGivesTheBarBackKeepingWhatIsHiddenAndResumingRestrictsTheSameApps() async {
        let rig = Rig()
        await rig.apply(.collapsed)
        let allowed = rig.provider.allowed
        let changes = rig.changes
        #expect(rig.hiding.suspend())
        #expect(rig.provider.log.last == "lift")
        #expect(rig.hiding.isRestricted)
        #expect(rig.hiding.hiddenApps.count == 2)
        #expect(!rig.hiding.suspend())
        rig.hiding.resume()
        #expect(rig.provider.log.suffix(2) == ["lift", "restrict"])
        #expect(rig.provider.allowed == allowed)
        #expect(rig.changes == changes)
        #expect(rig.hiding.suspend())
    }

    @Test func nothingIsSuspendedWhileNothingIsRestricted() async {
        let rig = Rig()
        #expect(!rig.hiding.suspend())
        await rig.apply(.collapsed)
        await rig.apply(.all)
        #expect(!rig.hiding.suspend())
        #expect(rig.provider.log == ["restrict", "lift"])
    }

    @Test func aChangeWhileSuspendedTakesOverAndTheResumeDoesNothing() async {
        let rig = Rig()
        await rig.apply(.collapsed)
        _ = rig.hiding.suspend()
        await rig.apply(.all)
        rig.hiding.resume()
        #expect(rig.provider.log == ["restrict", "lift", "lift"])
        #expect(!rig.hiding.isRestricted)
    }

    @Test func aResumeTheSystemRefusesLiftsAndIsReported() async {
        let rig = Rig()
        await rig.apply(.collapsed)
        _ = rig.hiding.suspend()
        rig.provider.takes = false
        rig.hiding.resume()
        #expect(rig.failures == 1)
        #expect(!rig.hiding.isRestricted)
    }
}
