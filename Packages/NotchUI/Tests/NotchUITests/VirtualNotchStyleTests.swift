import CoreGraphics
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import NotchUI

/// `interface.virtualNotchStyle`: whether the notch of a display without a hardware notch is stuck to the top edge or a pill that
/// floats a little below it. The setting, what is stored, that it reaches the code that redraws the notches, and that a display
/// with a hardware notch never feels it.
@Suite struct VirtualNotchStyleTests {
    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    // MARK: the setting

    @Test func theNotchIsTheDefaultSoNothingChangesUntilTheUserAsks() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        #expect(settings.value(InterfaceSettings.virtualNotchStyle) == .notch)
        #expect(NotchLayoutConfig().virtualNotchStyle == .notch)
        #expect(NotchLayoutConfig(settings: settings).virtualNotchStyle == .notch)
    }

    @Test func theKeyAndTheStoredNamesAreTheOnesTheAppKeepsAChoiceUnder() {
        #expect(InterfaceSettings.virtualNotchStyle.name == "interface.virtualNotchStyle")
        #expect(VirtualNotchStyle.allCases.map(\.rawValue) == ["notch", "pill"])
        let defaults = makeIsolatedDefaults()
        defaults.set(Data("\"pill\"".utf8), forKey: InterfaceSettings.virtualNotchStyle.name)
        #expect(SettingsStore(defaults: defaults).value(InterfaceSettings.virtualNotchStyle) == .pill)
    }

    @Test func eachChoiceIsKeptForTheNextLaunchAndResetGoesBackToTheNotch() {
        let defaults = makeIsolatedDefaults()
        for style in VirtualNotchStyle.allCases {
            SettingsStore(defaults: defaults).set(style, for: InterfaceSettings.virtualNotchStyle)
            #expect(SettingsStore(defaults: defaults).value(InterfaceSettings.virtualNotchStyle) == style)
        }
        let settings = SettingsStore(defaults: defaults)
        settings.set(.pill, for: InterfaceSettings.virtualNotchStyle)
        settings.reset(InterfaceSettings.virtualNotchStyle)
        #expect(settings.value(InterfaceSettings.virtualNotchStyle) == .notch)
    }

    @Test func anUnknownOrUnreadableStoredStyleIsTheDefault() {
        for stored in ["\"capsule\"", "\"\"", "7", "true", "null", "not json at all"] {
            let defaults = makeIsolatedDefaults()
            defaults.set(Data(stored.utf8), forKey: InterfaceSettings.virtualNotchStyle.name)
            #expect(SettingsStore(defaults: defaults).value(InterfaceSettings.virtualNotchStyle) == .notch, "\(stored)")
        }
    }

    @Test func theStyleLeavesTheOtherInterfaceSettingsAlone() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let before = NotchLayoutConfig(settings: settings)
        settings.set(.pill, for: InterfaceSettings.virtualNotchStyle)
        var after = NotchLayoutConfig(settings: settings)
        #expect(after.virtualNotchStyle == .pill)
        after.virtualNotchStyle = .notch
        #expect(after == before)
    }

    // MARK: live

    @Test func aChangeOfTheStyleReachesTheLoopThatRedrawsTheNotches() async {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        final class Seen { var styles: [VirtualNotchStyle] = [] }
        let seen = Seen()
        let loop = Task {
            for await config in Observations({ NotchLayoutConfig(settings: settings) }) { seen.styles.append(config.virtualNotchStyle) }
        }
        defer { loop.cancel() }
        #expect(await eventually { seen.styles.last == .notch })
        settings.set(.pill, for: InterfaceSettings.virtualNotchStyle)
        #expect(await eventually { seen.styles.last == .pill })
        settings.set(.notch, for: InterfaceSettings.virtualNotchStyle)
        #expect(await eventually { seen.styles.last == .notch })
    }

    @Test func theGeometryOfADisplayFollowsTheStyleAtOnce() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let screen = NotchGeometryTests.external
        #expect(NotchGeometry(screen: screen, config: NotchLayoutConfig(settings: settings)).isPill == false)
        settings.set(.pill, for: InterfaceSettings.virtualNotchStyle)
        let pill = NotchGeometry(screen: screen, config: NotchLayoutConfig(settings: settings))
        #expect(pill.isPill)
        settings.set(.notch, for: InterfaceSettings.virtualNotchStyle)
        #expect(NotchGeometry(screen: screen, config: NotchLayoutConfig(settings: settings)).isPill == false)
    }

    // MARK: only a display without a notch

    @Test func aHardwareNotchIsNeverAPillWhateverTheSettingSays() {
        let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig(virtualNotchStyle: .pill))
        #expect(geometry.kind == .hardware)
        #expect(geometry.style == .notch)
        #expect(!geometry.isPill)
        #expect(geometry.topGap == 0)
    }

    @Test func aDisplayWithoutANotchIsAPillOnlyWhenAsked() {
        let screen = NotchGeometryTests.external
        #expect(NotchGeometry(screen: screen, config: NotchLayoutConfig()).style == .notch)
        let pill = NotchGeometry(screen: screen, config: NotchLayoutConfig(virtualNotchStyle: .pill))
        #expect(pill.kind == .virtual)
        #expect(pill.style == .pill)
        #expect(pill.topGap == NotchGeometry.pillTopGap)
    }

    @Test func aHardwareNotchIsUnchangedInEveryMeasureTheStyleCouldReach() {
        let screen = NotchGeometryTests.macBook14
        let notch = NotchGeometry(screen: screen, config: NotchLayoutConfig())
        let pill = NotchGeometry(screen: screen, config: NotchLayoutConfig(virtualNotchStyle: .pill))
        let frame = screen.frame
        #expect(pill.notchSize == notch.notchSize)
        #expect(pill.centerOffset == notch.centerOffset)
        #expect(pill.panelSize == notch.panelSize)
        #expect(pill.panelFrame(in: frame) == notch.panelFrame(in: frame))
        #expect(pill.contentFrame(height: 190, in: frame) == notch.contentFrame(height: 190, in: frame))
        for state in [NotchState.closed, .compact, .open("a"), .open(nil), .toast] {
            #expect(pill.cornerRadii(for: state) == notch.cornerRadii(for: state), "\(state)")
            #expect(pill.shape(for: state) == notch.shape(for: state), "\(state)")
            #expect(pill.shapeSize(for: state, contentHeight: 170) == notch.shapeSize(for: state, contentHeight: 170), "\(state)")
            #expect(pill.hitRect(for: state, contentHeight: 170, in: frame) == notch.hitRect(for: state, contentHeight: 170, in: frame))
            #expect(pill.dragHitRect(for: state, in: frame) == notch.dragHitRect(for: state, in: frame))
        }
        for index in 0..<NotchGeometry.maxBubbles {
            #expect(pill.bubbleFrame(at: index) == notch.bubbleFrame(at: index))
            #expect(pill.bubbleScreenFrame(at: index, in: frame) == notch.bubbleScreenFrame(at: index, in: frame))
        }
        #expect(pill.bubbleCapacity == notch.bubbleCapacity)
        let points = stride(from: frame.midX - 400, through: frame.midX + 400, by: 13).flatMap { x in
            stride(from: frame.maxY - 300, through: frame.maxY, by: 11).map { CGPoint(x: x, y: $0) }
        }
        for state in [NotchState.closed, .compact, .open(nil), .toast] {
            for point in points {
                let a = pill.pointerZone(at: point, state: state, contentHeight: 170, strip: 30, bubbles: 2, listRows: 3, in: frame)
                let b = notch.pointerZone(at: point, state: state, contentHeight: 170, strip: 30, bubbles: 2, listRows: 3, in: frame)
                #expect(a == b)
            }
        }
    }

    // MARK: the notch style is today's, on a display without a notch too

    @Test func theNotchStyleOnADisplayWithoutANotchIsWhatItHasAlwaysBeenExceptThatTheOpenNotchStartsAtTheTop() {
        let screen = NotchGeometryTests.external
        let geometry = NotchGeometry(screen: screen, config: NotchLayoutConfig(virtualNotchStyle: .notch))
        let frame = screen.frame
        #expect(geometry.topGap == 0)
        #expect(geometry.shapeSize(for: .closed) == CGSize(width: 185 + 12, height: 25))
        #expect(geometry.shapeSize(for: .compact) == CGSize(width: 185 + 12 + 128, height: 25))
        // No cutout to keep free: the tab page starts the padding below the top, not the notch's 25 pt.
        #expect(geometry.shapeSize(for: .open(nil), contentHeight: 190) == CGSize(width: 600, height: 14 + 190))
        #expect(geometry.cornerRadii(for: .closed) == (6, 10))
        #expect(geometry.cornerRadii(for: .compact) == (6, 10))
        #expect(geometry.cornerRadii(for: .open(nil)) == (8, 24))
        #expect(geometry.cornerRadii(for: .toast) == (8, 24))
        #expect(geometry.panelSize == CGSize(width: 900, height: 25 + 240))
        #expect(geometry.panelFrame(in: frame) == CGRect(x: 1512 + 960 - 450, y: 1080 - 265, width: 900, height: 265))
        #expect(geometry.hitRect(for: .closed, in: frame) == CGRect(x: 2472 - 98.5 - 8, y: 1080 - 25 - 8, width: 197 + 16, height: 25 + 8 + 1))
        #expect(geometry.bubbleFrame(at: 0) == CGRect(x: 162.5, y: 0, width: 25, height: 25))
        #expect(geometry.contentFrame(height: 100, in: frame) == CGRect(x: 2472 - 300 + 22, y: 1080 - 14 - 100, width: 556, height: 100))
        for state in [NotchState.closed, .compact, .open(nil), .toast] {
            let radii = geometry.cornerRadii(for: state)
            #expect(geometry.shape(for: state) == NotchShape(topRadius: radii.top, bottomRadius: radii.bottom))
            #expect(geometry.shape(for: state).cornerRadius == 0)
        }
    }
}
