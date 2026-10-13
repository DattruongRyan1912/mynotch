import CoreGraphics
import Foundation
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
        #expect(tab(120).contentHeight == 120)
        #expect(tab(300).contentHeight == 300)
    }

    @Test func moduleErrorsMapToStates() {
        #expect(ModuleState(.needsPermission(.accessibility)) == .needsPermission(.accessibility))
        #expect(ModuleState(.unavailable(reason: "r")) == .unavailable(reason: "r"))
        #expect(ModuleState(.failed(reason: "f")) == .failed(reason: "f"))
    }

    @Test(arguments: [
        (Permission.accessibility, "Privacy_Accessibility"),
        (.screenRecording, "Privacy_ScreenCapture"),
        (.calendars, "Privacy_Calendars"),
        (.reminders, "Privacy_Reminders"),
        (.bluetooth, "Privacy_Bluetooth"),
        (.automation(bundleID: "com.spotify.client"), "Privacy_Automation"),
        (.microphone, "Privacy_Microphone"),
    ])
    func permissionsDeepLinkToPrivacyPanes(permission: Permission, anchor: String) {
        #expect(permission.settingsURL == "x-apple.systempreferences:com.apple.preference.security?" + anchor)
    }

    @Test func moduleIDValidatesRuntimeValuesAndCodesAsPlainString() throws {
        #expect(ModuleID(rawValue: "battery2")?.rawValue == "battery2")
        for invalid in ["", "Battery", "a.b", "a_b", "café", "app"] {
            #expect(ModuleID(rawValue: invalid) == nil)
        }
        let encoded = try JSONEncoder().encode(ModuleID("battery"))
        #expect(String(decoding: encoded, as: UTF8.self) == "\"battery\"")
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ModuleID.self, from: Data("\"Bad.ID\"".utf8)) }
    }

    @Test func priorityOrdering() {
        #expect(ActivityPriority.low < .normal && .normal < .high && .high < .critical)
    }
}
