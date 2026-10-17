import AppKit
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import EqualizerModule

/// The tab has to fit the room the notch gives a tab, in its tallest state too. Measured, not drawn: nothing is put on screen.
@Suite struct EqualizerTabLayoutTests {
    /// The narrowest open notch is 480 pt wide, 2 x (8 + the notch's padding) of it taken.
    static let width: CGFloat = 480 - 2 * (8 + NotchTokens.padding)
    static let longName = "Tai nghe không dây có tên rất dài của một người dùng nào đó"

    let defaults = makeIsolatedDefaults()
    let state: EqualizerState

    init() {
        state = EqualizerState(settings: SettingsStore(defaults: defaults))
    }

    func fittingHeight(of phase: EqualizerStatus.Phase, eqMac: Bool = false) -> CGFloat {
        let status = EqualizerStatus()
        status.phase = phase
        status.eqMacRunning = eqMac
        let tab = EqualizerTabView(state: state, status: status, actions: EqualizerTabActions(appeared: {}, openSettings: {}, retry: {}))
            .frame(width: Self.width)
        return NSHostingView(rootView: tab).fittingSize.height
    }

    var phases: [(String, EqualizerStatus.Phase, Bool)] {
        [
            ("off", .off, false),
            ("waiting", .waiting, false),
            ("one device", .processing(["MacBook Pro Speakers"]), false),
            ("long list of devices", .processing([Self.longName, Self.longName, Self.longName]), false),
            ("permission hint", .needsPermission, false),
            ("long failure", .failed(Self.longName + ": " + Self.longName + ": " + Self.longName), false),
            ("eqMac warning", .waiting, true),
        ]
    }

    @Test func everyStateFitsTheHeightTheTabDeclares() {
        for (name, phase, eqMac) in phases {
            let height = fittingHeight(of: phase, eqMac: eqMac)
            #expect(height <= EqualizerTabView.contentHeight, "\(name): \(height) pt")
        }
    }

    @Test func theDeclaredHeightIsNotMuchMoreThanTheTallestStateNeeds() {
        let tallest = phases.map { fittingHeight(of: $0.1, eqMac: $0.2) }.max() ?? 0
        #expect(tallest > EqualizerTabView.contentHeight - 12, "\(tallest) pt")
    }

    @Test func theTabDoesNotChangeHeightWhenTheLineChanges() {
        // Otherwise the sliders would jump when a device starts or stops playing.
        let heights = Set(phases.map { fittingHeight(of: $0.1, eqMac: $0.2) })
        #expect(heights.count == 1, "\(heights.sorted())")
    }

    @Test func theHeightTheTabAsksForIsItsContentPlusTheNotchsPaddingAndTheTabBar() {
        #expect(EqualizerTabView.preferredHeight == EqualizerTabView.contentHeight + NotchTokens.padding + EqualizerTabView.tabBarHeight)
        #expect(EqualizerTabView.preferredHeight <= NotchTab.heightRange.upperBound)
        #expect(EqualizerTabView.preferredHeight >= NotchTab.heightRange.lowerBound)
    }

    /// The tab cuts a line at two lines; the lines the module writes itself must not need the cut.
    @Test func theTextsTheModuleWritesFitTwoLines() {
        let lines: [(String, EqualizerStatus.Phase, Bool)] = [
            ("one device", .processing(["MacBook Pro Speakers"]), false),
            ("two devices", .processing(["MacBook Pro Speakers", "AirPods của Ryan"]), false),
            ("permission", .needsPermission, false),
            ("eqMac", .waiting, true),
            ("failure", .failed("Loa Bluetooth: không dựng được"), false),
        ]
        for (name, phase, eqMac) in lines {
            let status = EqualizerStatus()
            status.phase = phase
            status.eqMacRunning = eqMac
            let line = EQStatusLine(status: status, actions: EqualizerTabActions(appeared: {}, openSettings: {}, retry: {}), lineLimit: nil)
                .frame(width: Self.width)
                .fixedSize(horizontal: false, vertical: true)
            let height = NSHostingView(rootView: line).fittingSize.height
            #expect(height <= EQStatusLine.height, "\(name): \(height) pt")
        }
    }

    @Test func noProfilesStillFits() {
        for profile in state.profiles { state.delete(profile.id) }
        #expect(fittingHeight(of: .waiting) <= EqualizerTabView.contentHeight)
    }
}
