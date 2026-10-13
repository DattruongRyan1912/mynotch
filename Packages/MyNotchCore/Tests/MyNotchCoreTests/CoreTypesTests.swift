import CoreGraphics
import SwiftUI
import Testing
@testable import MyNotchCore

@Suite struct CoreTypesTests {
    @Test func tabHeightIsClampedWithDefault() {
        func tab(_ height: CGFloat?) -> NotchTab {
            NotchTab(id: "x", title: "X", systemImage: "circle", preferredHeight: height, content: AnyView(EmptyView()))
        }
        #expect(tab(nil).contentHeight == 190)
        #expect(tab(50).contentHeight == 120)
        #expect(tab(500).contentHeight == 300)
    }

    @Test func moduleErrorsMapToStates() {
        #expect(ModuleState(.needsPermission(.accessibility)) == .needsPermission(.accessibility))
        #expect(ModuleState(.unavailable(reason: "r")) == .unavailable(reason: "r"))
        #expect(ModuleState(.failed(reason: "f")) == .failed(reason: "f"))
    }

    @Test func permissionsDeepLinkToPrivacyPanes() {
        #expect(Permission.accessibility.settingsURL.hasSuffix("?Privacy_Accessibility"))
        #expect(Permission.automation(bundleID: "com.spotify.client").settingsURL.hasSuffix("?Privacy_Automation"))
    }

    @Test func priorityOrdering() {
        #expect(ActivityPriority.low < .normal && .normal < .high && .high < .critical)
    }
}
