import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MyNotch

@Suite("DashboardTab Tests")
@MainActor
struct DashboardTabTests {
    @Test func testAudioTabProperties() {
        let tab = DashboardTab.audio
        #expect(tab.rawValue == "audio")
        #expect(tab.id == "audio")
        #expect(tab.title == "Âm thanh & EQ")
        #expect(tab.icon == "slider.vertical.3")
        #expect(tab.iconColor == DashboardTheme.infoAccent)
    }

    @Test func testAudioTabRawValueParsing() {
        #expect(DashboardTab(rawValue: "audio") == .audio)
        #expect(DashboardTab(rawValue: "sound") == .audio)
        #expect(DashboardTab(rawValue: "equalizer") == .audio)
        #expect(DashboardTab(rawValue: "invalid_tab_xyz") == nil)
    }

    @Test func testAllCasesIncludesAudio() {
        #expect(DashboardTab.allCases.contains(.audio))
        #expect(DashboardTab.allCases.contains(.overview))
        #expect(DashboardTab.allCases.contains(.battery))
        #expect(DashboardTab.allCases.contains(.hardware))
        #expect(DashboardTab.allCases.contains(.cleaner))
    }
}
