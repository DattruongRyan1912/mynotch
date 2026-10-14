import AppKit
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import NotchUI

@Suite struct CaptureHidingTests {
    let states: [NotchState] = [.closed, .compact, .open(nil), .open("clipboard"), .toast]

    @Test func neverLeavesTheWindowNormalInEveryState() {
        for state in states {
            #expect(CaptureHiding.never.sharingType(for: state) == .readOnly, "\(state)")
        }
    }

    @Test func alwaysHidesTheWindowInEveryState() {
        for state in states {
            #expect(CaptureHiding.always.sharingType(for: state) == .none, "\(state)")
        }
    }

    @Test func whenCollapsedHidesTheClosedAndCompactNotchAndShowsTheExpandedOne() {
        #expect(CaptureHiding.whenCollapsed.sharingType(for: .closed) == .none)
        #expect(CaptureHiding.whenCollapsed.sharingType(for: .compact) == .none)
        #expect(CaptureHiding.whenCollapsed.sharingType(for: .open(nil)) == .readOnly)
        #expect(CaptureHiding.whenCollapsed.sharingType(for: .open("clipboard")) == .readOnly)
        #expect(CaptureHiding.whenCollapsed.sharingType(for: .toast) == .readOnly)
    }

    @Test func theSettingDefaultsToNotHidingAndKeepsItsStoredNames() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        #expect(settings.value(InterfaceSettings.hideFromCapture) == .never)
        for (value, name) in [(CaptureHiding.never, "never"), (.whenCollapsed, "whenCollapsed"), (.always, "always")] {
            #expect(value.rawValue == name)
            settings.set(value, for: InterfaceSettings.hideFromCapture)
            #expect(settings.value(InterfaceSettings.hideFromCapture) == value)
        }
    }
}
