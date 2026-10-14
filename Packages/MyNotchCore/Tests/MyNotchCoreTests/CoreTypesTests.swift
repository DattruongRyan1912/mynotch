import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

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

    @Test func tabsDoNotTakeTheKeyboardUnlessTheyAskForIt() {
        #expect(!NotchTab(id: "x", title: "X", systemImage: "circle", content: AnyView(EmptyView())).acceptsKeyboard)
        #expect(NotchTab(id: "x", title: "X", systemImage: "circle", acceptsKeyboard: true, content: AnyView(EmptyView())).acceptsKeyboard)
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

    @Test func onlyAccessibilityAndScreenRecordingAreSettingsOnly() {
        let settingsOnly: [Permission] = [.accessibility, .screenRecording]
        let promptable: [Permission] = [.calendars, .reminders, .bluetooth, .automation(bundleID: "com.spotify.client"), .microphone]
        #expect(settingsOnly.allSatisfy { $0.isSettingsOnly })
        #expect(!promptable.contains { $0.isSettingsOnly })
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

    // MARK: the strip under the notch

    @Test func anActivityHasNoBottomStripUnlessItAsksForOne() {
        let plain = activity("x")
        #expect(plain.bottom == nil)
        #expect(plain.bottomHeight == 0)
        #expect(!plain.hasBottom)

        // The initialiser every module already calls, with all of its labels.
        let full = LiveActivity(id: "y", priority: .high, expiresAfter: .seconds(3), leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()))
        #expect(full.priority == .high && full.expiresAfter == .seconds(3))
        #expect(!full.hasBottom)
    }

    @Test func aBottomStripCarriesItsViewAndHeight() {
        let strip = LiveActivity(
            id: "x", leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()),
            bottom: AnyView(Text("under")), bottomHeight: 36
        )
        #expect(strip.bottom != nil)
        #expect(strip.bottomHeight == 36)
        #expect(strip.hasBottom)
    }

    @Test func aStripNeedsBothAViewAndAHeightToTakeSpace() {
        let noHeight = LiveActivity(id: "x", leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()), bottom: AnyView(Text("under")))
        #expect(noHeight.bottomHeight == 0 && !noHeight.hasBottom)
        let negative = LiveActivity(
            id: "x", leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()), bottom: AnyView(Text("under")), bottomHeight: -5
        )
        #expect(negative.bottomHeight == 0 && !negative.hasBottom)
        let noView = LiveActivity(id: "x", leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()), bottomHeight: 36)
        #expect(noView.bottom == nil && noView.bottomHeight == 0 && !noView.hasBottom)
    }

    @Test func theCenterHandsOnTheCurrentActivitysStrip() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(LiveActivity(
            id: "m", leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()), bottom: AnyView(Text("under")), bottomHeight: 36
        ), from: "one")
        #expect(center.current?.activity.hasBottom == true)
        center.set(activity("m"), from: "one")
        #expect(center.current?.activity.hasBottom == false)
    }
}
