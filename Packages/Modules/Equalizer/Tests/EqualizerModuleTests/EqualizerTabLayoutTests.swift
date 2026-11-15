import AppKit
import EqualizerAudio
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import EqualizerModule

private func findSubviews<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
    var res: [T] = []
    for sub in view.subviews {
        if let match = sub as? T { res.append(match) }
        res.append(contentsOf: findSubviews(of: type, in: sub))
    }
    return res
}

/// The tab has to fit the room the notch gives a tab, in its tallest state too. Measured, not drawn: nothing is put on screen.
@Suite(.serialized) struct EqualizerTabLayoutTests {
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

    @Test func deepBassProfileAndMaxGainsFitDeclaredHeight() throws {
        let deepBass = try #require(state.profiles.first(where: { $0.name == "Deep Bass (eqMac)" }))
        state.select(deepBass.id)
        let height = fittingHeight(of: .processing(["AirPods Max"]))
        #expect(height <= EqualizerTabView.contentHeight, "Deep Bass profile must fit within \(EqualizerTabView.contentHeight) pt, got \(height)")

        // Extreme ±24 dB band gains and extreme -11.5 dB preamp must also fit without height distortion or clipping
        state.setGain(24, band: 0)
        state.setGain(-24, band: 1)
        state.setPreamp(-11.5)
        let extremeHeight = fittingHeight(of: .processing(["AirPods Max"]))
        #expect(extremeHeight <= EqualizerTabView.contentHeight, "Extreme gains and preamp must fit within \(EqualizerTabView.contentHeight) pt, got \(extremeHeight)")
    }

    private static var tabEventCounter: Int = 2000

    @Test func equalizerSettingsViewFitsStandardSettingsWindowSizes() async throws {
        let viewports: [(w: CGFloat, h: CGFloat, name: String)] = [
            (680, 480, "Standard Compact Settings (680x480)"),
            (860, 600, "Default Settings Window (860x600)"),
            (1100, 800, "Expanded Studio Settings (1100x800)")
        ]
        for vp in viewports {
            var openSettingsTriggered = false
            let status = EqualizerStatus()
            status.phase = .processing(["MacBook Pro Speakers"])
            status.activeDeviceTelemetries = [
                EQDeviceTelemetry(uid: "uid1", name: "MacBook Pro Speakers", sampleRate: 48000, volumePercent: 75, channelCount: 2, isProcessing: true)
            ]
            let settingsView = EqualizerSettingsView(
                state: state,
                status: status,
                isRunning: true,
                openSettings: { openSettingsTriggered = true },
                retry: {}
            )

            // 1. Measure constrained fitting width of the settings content
            let contentHosting = NSHostingView(rootView: settingsView.frame(width: vp.w))
            contentHosting.layoutSubtreeIfNeeded()
            let contentFit = contentHosting.fittingSize
            #expect(contentFit.width <= vp.w + 1.0, "[\(vp.name)] Settings content width \(contentFit.width) must not overflow viewport width \(vp.w)")

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: vp.w, height: vp.h),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: vp.w, height: vp.h))
            scrollView.hasVerticalScroller = true
            let docHeight = max(vp.h, contentFit.height)
            contentHosting.frame = NSRect(x: 0, y: 0, width: vp.w, height: docHeight)
            scrollView.documentView = contentHosting
            window.contentView = scrollView
            window.makeKeyAndOrderFront(nil)
            window.displayIfNeeded()
            scrollView.frame = NSRect(x: 0, y: 0, width: vp.w, height: vp.h)
            scrollView.layoutSubtreeIfNeeded()
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)

            #expect(contentHosting.frame.width == vp.w, "[\(vp.name)] Document view width must match window width \(vp.w)")
            #expect(contentHosting.frame.height >= vp.h, "[\(vp.name)] Document view height must accommodate content")

            // 2. 10-Band Horizontal Containment & Hit-Testing Verification Across Viewports
            let allInitialViews = findSubviews(of: NSView.self, in: contentHosting)
            let bandSliders = allInitialViews.filter { sub in
                let f = sub.convert(sub.bounds, to: contentHosting)
                return f.width >= 12 && f.width <= 24 && f.height >= 50 && f.height <= 80 && sub.subviews.isEmpty
            }
            Swift.print("[\(vp.name)] Located \(bandSliders.count) band sliders")
            #expect(bandSliders.count == 10, "[\(vp.name)] Exactly 10 band sliders must be present in view hierarchy, found \(bandSliders.count)")

            for (idx, slider) in bandSliders.enumerated() {
                let f = slider.convert(slider.bounds, to: contentHosting)
                Swift.print("  band \(idx): \(type(of: slider)) frame=\(f)")
                #expect(f.minX >= 0.0, "[\(vp.name)] Band \(idx) minX (\(f.minX)) must be >= 0")
                #expect(f.maxX <= vp.w, "[\(vp.name)] Band \(idx) maxX (\(f.maxX)) must not overflow viewport width (\(vp.w))")

                // Hit-testing check: the center of each band must hit a valid interactive view in the window
                let centerInWindow = slider.convert(NSPoint(x: slider.bounds.midX, y: slider.bounds.midY), to: nil)
                let hitView = window.contentView?.hitTest(centerInWindow)
                #expect(hitView != nil, "[\(vp.name)] Band \(idx) at \(centerInWindow) must hit a valid view, got nil")
            }

            // 3. Scroll to bottom verification: verify actual scroll offset and visibility of bottom telemetry controls
            let clipHeight = scrollView.contentView.bounds.height
            let maxScrollY = max(0, docHeight - clipHeight)
            if maxScrollY > 0 {
                // Scroll to bottom
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxScrollY))
                scrollView.reflectScrolledClipView(scrollView.contentView)

                let visibleRect = scrollView.contentView.documentVisibleRect
                #expect(visibleRect.origin.y >= maxScrollY - 2.0, "[\(vp.name)] Actual scroll offset \(visibleRect.origin.y) must reach bottom \(maxScrollY)")
                #expect(visibleRect.maxY >= docHeight - 2.0, "[\(vp.name)] Visible rect maxY \(visibleRect.maxY) must reach content bottom \(docHeight)")

                // Identify actual telemetry control ("Mở System Settings" button)
                let allViews = findSubviews(of: NSView.self, in: contentHosting)
                let telemetryButtons = allViews.filter { sub in
                    let f = sub.convert(sub.bounds, to: contentHosting)
                    return f.width >= 110 && f.width <= 145 && f.height >= 14 && f.height <= 26 && f.maxY >= docHeight - 120
                }
                Swift.print("[\(vp.name)] found \(telemetryButtons.count) candidates:")
                for b in telemetryButtons {
                    Swift.print("  candidate: \(type(of: b)) frame=\(b.frame) converted=\(b.convert(b.bounds, to: contentHosting))")
                }
                let telemetryButton = try #require(telemetryButtons.first, "[\(vp.name)] 'Mở System Settings' button must be present in bottom telemetry section")
                let controlFrame = telemetryButton.convert(telemetryButton.bounds, to: contentHosting)

                // Prove visibleRect fully CONTAINS the telemetry control frame (not merely intersects)
                #expect(visibleRect.contains(controlFrame), "[\(vp.name)] visibleRect \(visibleRect) must fully contain telemetry control at \(controlFrame)")

                // Dispatch native mouse click event to prove interactivity
                let clickPointInWindow = telemetryButton.convert(NSPoint(x: telemetryButton.bounds.midX, y: telemetryButton.bounds.midY), to: nil)
                Self.tabEventCounter += 1
                let downNum = Self.tabEventCounter
                Self.tabEventCounter += 1
                let upNum = Self.tabEventCounter
                let t = ProcessInfo.processInfo.systemUptime + Double(downNum) * 0.1
                let hit = window.contentView?.hitTest(clickPointInWindow)
                Swift.print("[\(vp.name)] docHeight=\(docHeight) clickPt=\(clickPointInWindow) hit=\(String(describing: hit))")

                let down = NSEvent.mouseEvent(
                    with: .leftMouseDown,
                    location: clickPointInWindow,
                    modifierFlags: [],
                    timestamp: t,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: downNum,
                    clickCount: 1,
                    pressure: 1.0
                )!
                let up = NSEvent.mouseEvent(
                    with: .leftMouseUp,
                    location: clickPointInWindow,
                    modifierFlags: [],
                    timestamp: t + 0.02,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: upNum,
                    clickCount: 1,
                    pressure: 0.0
                )!
                window.sendEvent(down)
                window.sendEvent(up)
                for _ in 0..<20 where !openSettingsTriggered {
                    await Task.yield()
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
                #expect(openSettingsTriggered == true, "[\(vp.name)] Dispatching click to telemetry button must trigger openSettings callback")
            } else {
                let visibleRect = scrollView.contentView.documentVisibleRect
                #expect(visibleRect.height >= contentFit.height - 2.0, "[\(vp.name)] All content must be fully visible without scrolling on expanded window")

                // Also verify telemetry button is contained in visibleRect on expanded window
                let allViews = findSubviews(of: NSView.self, in: contentHosting)
                let telemetryButtons = allViews.filter { sub in
                    let f = sub.convert(sub.bounds, to: contentHosting)
                    return f.width >= 110 && f.width <= 145 && f.height >= 14 && f.height <= 26 && f.maxY >= docHeight - 120
                }
                let telemetryButton = try #require(telemetryButtons.first, "[\(vp.name)] 'Mở System Settings' button must be present")
                let controlFrame = telemetryButton.convert(telemetryButton.bounds, to: contentHosting)
                #expect(visibleRect.contains(controlFrame), "[\(vp.name)] visibleRect \(visibleRect) must fully contain telemetry control at \(controlFrame)")

                let clickPointInWindow = telemetryButton.convert(NSPoint(x: telemetryButton.bounds.midX, y: telemetryButton.bounds.midY), to: nil)
                Self.tabEventCounter += 1
                let downNum = Self.tabEventCounter
                Self.tabEventCounter += 1
                let upNum = Self.tabEventCounter
                let t = ProcessInfo.processInfo.systemUptime + Double(downNum) * 0.1
                let hit = window.contentView?.hitTest(clickPointInWindow)
                Swift.print("[\(vp.name)] expanded clickPt=\(clickPointInWindow) hit=\(String(describing: hit))")

                let down = NSEvent.mouseEvent(
                    with: .leftMouseDown,
                    location: clickPointInWindow,
                    modifierFlags: [],
                    timestamp: t,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: downNum,
                    clickCount: 1,
                    pressure: 1.0
                )!
                let up = NSEvent.mouseEvent(
                    with: .leftMouseUp,
                    location: clickPointInWindow,
                    modifierFlags: [],
                    timestamp: t + 0.02,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: upNum,
                    clickCount: 1,
                    pressure: 0.0
                )!
                window.sendEvent(down)
                window.sendEvent(up)
                for _ in 0..<20 where !openSettingsTriggered {
                    await Task.yield()
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
                #expect(openSettingsTriggered == true, "[\(vp.name)] Dispatching click on expanded window must trigger openSettings")
            }
        }
    }
}
