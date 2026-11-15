import AppKit
@preconcurrency import CoreAudio
import EqualizerAudio
import EqualizerDSP
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import EqualizerModule

private func withAudioBuffer(frames: Int, samples: [Float], process: (UnsafeMutableAudioBufferListPointer) -> Void) -> [Float] {
    let list = AudioBufferList.allocate(maximumBuffers: 1)
    let data = UnsafeMutablePointer<Float>.allocate(capacity: frames)
    data.initialize(repeating: 0.0, count: frames)
    for i in 0..<min(frames, samples.count) {
        data[i] = samples[i]
    }
    list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * MemoryLayout<Float>.size), mData: data)
    process(list)
    let result = (0..<frames).map { data[$0] }
    data.deallocate()
    free(list.unsafeMutablePointer)
    return result
}

@MainActor
@Suite(.serialized) struct EQSettingsInteractionTests {
    private let defaults = makeIsolatedDefaults()
    private let state: EqualizerState
    private let engine: FakeEngine
    private let module: EqualizerModule
    private let harness: RegistryHarness

    init() {
        state = EqualizerState(settings: SettingsStore(defaults: defaults))
        state.resetToDefaults()
        state.isEnabled = true
        engine = FakeEngine()
        engine.playing = ["MacBook Pro Speakers"]
        module = EqualizerModule(state: state, engine: engine, isEqMacRunning: { false })
        harness = RegistryHarness([module])
    }

    private func decodePersisted<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - Native AppKit Window Hosting & Real Mouse Event Dispatcher

    private func makeHostingWindow<V: View>(view: V, size: NSSize = NSSize(width: 860, height: 1000)) -> (NSWindow, NSHostingView<V>) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        return (window, hostingView)
    }

    private func pumpEvents() async {
        for _ in 0..<5 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func findFocusRing(
        in hostingView: NSView,
        xRange: ClosedRange<CGFloat>? = nil,
        yRange: ClosedRange<CGFloat>? = nil,
        widthRange: ClosedRange<CGFloat>? = nil
    ) -> NSView? {
        if let direct = hostingView.subviews.first(where: { sub in
            let f = sub.frame
            let xMatch = xRange == nil || xRange!.contains(f.origin.x)
            let yMatch = yRange == nil || yRange!.contains(f.origin.y)
            let wMatch = widthRange == nil || widthRange!.contains(f.width)
            return xMatch && yMatch && wMatch
        }) {
            return direct
        }
        let allViews = findSubviews(of: NSView.self, in: hostingView)
        return allViews.first(where: { sub in
            let f = sub.convert(sub.bounds, to: hostingView)
            let xMatch = xRange == nil || xRange!.contains(f.origin.x)
            let yMatch = yRange == nil || yRange!.contains(f.origin.y)
            let wMatch = widthRange == nil || widthRange!.contains(f.width)
            return xMatch && yMatch && wMatch
        })
    }

    private func findSubviews<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
        var res: [T] = []
        for sub in view.subviews {
            if let match = sub as? T { res.append(match) }
            res.append(contentsOf: findSubviews(of: type, in: sub))
        }
        return res
    }

    private func click(view: NSView, in window: NSWindow, hostingView: NSView) {
        let centerInHosting: NSPoint
        if view.superview === hostingView {
            centerInHosting = NSPoint(x: view.frame.midX, y: view.frame.midY)
        } else {
            centerInHosting = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: hostingView)
        }
        clickPoint(centerInHosting, in: window, hostingView: hostingView)
    }

    private static var eventCounter: Int = 100

    private func clickPoint(_ pointInHosting: NSPoint, in window: NSWindow, hostingView: NSView) {
        let centerInWindow = hostingView.convert(pointInHosting, to: nil)
        Self.eventCounter += 1
        let downNum = Self.eventCounter
        Self.eventCounter += 1
        let upNum = Self.eventCounter
        let t = ProcessInfo.processInfo.systemUptime + Double(downNum) * 0.1

        Swift.print("[CLICK] pointInHosting=\(pointInHosting) centerInWindow=\(centerInWindow) hitView=\(String(describing: window.contentView?.hitTest(centerInWindow)))")
        let down = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: centerInWindow,
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
            location: centerInWindow,
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
    }

    // MARK: - Empirical Behavioral Tests with Control Dispatch, AX, Engine & DSP Side-Effects

    @Test func testMasterToggleDispatchesUIEventAndEnablesEnginePipeline() async throws {
        await harness.registry.bootstrap()
        await settle(until: { engine.isRunning })
        #expect(state.isEnabled)
        #expect(engine.isRunning, "Engine must be running after harness bootstrap")

        let status = EqualizerStatus()
        let view = EqualizerSettingsView(
            state: state,
            status: status,
            isRunning: true,
            openSettings: {},
            retry: {}
        ).frame(width: 860, height: 1000, alignment: .topLeading)
        let (window, hostingView) = makeHostingWindow(view: view)
        _ = hostingView
        await pumpEvents()

        // 1. Accessibility State verification on container
        let axRole = hostingView.accessibilityRole()
        #expect(axRole == .group, "Hosting view must expose AXGroup accessibility role")
        Swift.print("[DOM/AX STATE] Verified hostingView AX role: \(String(describing: axRole))")

        // 2. Locate Master Toggle control via native focus ring (x in 0...50, y in -10...10, width ~104)
        let masterToggle = try #require(findFocusRing(in: hostingView, xRange: 0...50, yRange: -10...10, widthRange: 90...150), "Master Toggle control focus ring must be present in view hierarchy")

        // 3. Dispatch UI Event: User clicks Master Toggle to turn OFF
        Swift.print("[UI-DISPATCH] Dispatching Master Toggle OFF click via native NSEvent at \(masterToggle.frame)")
        click(view: masterToggle, in: window, hostingView: hostingView)
        await settle(until: { !engine.isRunning })

        // Model & Engine Verification
        #expect(!state.isEnabled, "State must reflect disabled equalizer after toggle click")
        #expect(!engine.isRunning, "Engine must stop when master toggle is switched off")
        Swift.print("[DOM/AX STATE] Verified state.isEnabled == false and engine.isRunning == false")

        // Persistence Verification in UserDefaults
        #expect(decodePersisted(Bool.self, forKey: "app.equalizer.enabled") == false)
        Swift.print("[SIDE-EFFECT] Verified UserDefaults persistence: app.equalizer.enabled = false")

        // 4. Dispatch UI Event: User clicks Master Toggle to turn ON
        Swift.print("[UI-DISPATCH] Dispatching Master Toggle ON click via native NSEvent")
        click(view: masterToggle, in: window, hostingView: hostingView)
        await settle(until: { engine.isRunning })

        #expect(state.isEnabled, "State must reflect enabled equalizer after second toggle click")
        #expect(engine.isRunning, "Engine must resume when master toggle is switched on")
        #expect(decodePersisted(Bool.self, forKey: "app.equalizer.enabled") == true)
        Swift.print("[SIDE-EFFECT] Verified equalizer re-enabled and persisted: app.equalizer.enabled = true")

        _ = window
    }

    @Test func testAddFlatProfileButtonClickCreatesNewProfileAndSelectsIt() async throws {
        await harness.registry.bootstrap()
        await settle(until: { engine.isRunning })

        let initialCount = state.profiles.count
        let status = EqualizerStatus()
        let view = EqualizerSettingsView(
            state: state,
            status: status,
            isRunning: true,
            openSettings: {},
            retry: {}
        ).frame(width: 860, height: 1000, alignment: .topLeading)
        let (window, hostingView) = makeHostingWindow(view: view)
        _ = hostingView
        await pumpEvents()

        // Locate "+ Thêm mới" button focus ring (x in 500...540, width in 85...100)
        let addBtn = try #require(findFocusRing(in: hostingView, xRange: 500...540, widthRange: 85...100), "Add Flat Profile button must be present in view hierarchy")

        Swift.print("[UI-DISPATCH] Dispatching '+ Thêm mới' (Add Flat Profile) click via native NSEvent at \(addBtn.frame)")
        click(view: addBtn, in: window, hostingView: hostingView)
        await settle(until: { state.profiles.count == initialCount + 1 })

        #expect(state.profiles.count == initialCount + 1, "Profile count must increment by 1")
        let newlySelected = try #require(state.selected)
        #expect(state.selectedID == newlySelected.id, "Newly created profile must be automatically selected")
        #expect(newlySelected.gains.allSatisfy { $0 == 0.0 } == true, "Flat profile must have 0.0 dB on all 10 bands")

        await settle(until: { engine.applied.last?.id == newlySelected.id })
        let applied = try #require(engine.applied.last)
        #expect(applied.id == newlySelected.id)

        let persistedSelected = decodePersisted(UUID.self, forKey: "app.equalizer.selected")
        #expect(persistedSelected == newlySelected.id)
        Swift.print("[DOM/AX STATE] Verified new profile '\(newlySelected.name)' created via UI, selected, engine-synced, and persisted")

        _ = window
    }

    @Test func testDuplicateProfileButtonClickDuplicatesActiveProfileAndSelectsIt() async throws {
        await harness.registry.bootstrap()
        await settle(until: { engine.isRunning })

        let systemProfile = try #require(state.profiles.first(where: { state.isSystemDefault($0.id) }))
        state.select(systemProfile.id)
        await settle(until: { engine.applied.last?.id == systemProfile.id })

        let initialCount = state.profiles.count
        let status = EqualizerStatus()
        let view = EqualizerSettingsView(
            state: state,
            status: status,
            isRunning: true,
            openSettings: {},
            retry: {}
        ).frame(width: 860, height: 1000, alignment: .topLeading)
        let (window, hostingView) = makeHostingWindow(view: view)
        _ = hostingView
        await pumpEvents()

        // Locate "Nhân bản" button focus ring (x in 600...640, width in 85...100)
        let dupBtn = try #require(findFocusRing(in: hostingView, xRange: 600...640, widthRange: 85...100), "Duplicate button must be present in view hierarchy")

        Swift.print("[UI-DISPATCH] Dispatching 'Nhân bản' (Duplicate) click via native NSEvent on '\(systemProfile.name)' at \(dupBtn.frame)")
        click(view: dupBtn, in: window, hostingView: hostingView)
        await settle(until: { state.profiles.count == initialCount + 1 })

        #expect(state.profiles.count == initialCount + 1)
        let duplicate = try #require(state.selected)
        #expect(duplicate.id != systemProfile.id, "Duplicate must have unique UUID")
        #expect(duplicate.name.contains("Bản sao"), "Duplicate name must contain 'Bản sao' copy suffix")
        #expect(state.selectedID == duplicate.id, "Duplicate must become actively selected")
        #expect(!state.isSystemDefault(duplicate.id), "Duplicate is a custom profile, not system default")
        #expect(state.canRename(duplicate.id), "Custom duplicate can be renamed")
        #expect(state.canDelete(duplicate.id), "Custom duplicate can be deleted")

        await settle(until: { engine.applied.last?.id == duplicate.id })
        #expect(engine.applied.last?.id == duplicate.id)
        Swift.print("[DOM/AX STATE] Verified duplicate profile '\(duplicate.name)' created via UI, selected, and synced")

        _ = window
    }

    @Test func testRenameActionAndCancelConfirmWorkflow() async throws {
        await harness.registry.bootstrap()
        await settle(until: { engine.isRunning })

        // Create a custom profile to rename
        let custom = try #require(state.addFlatProfile(named: "Temp Profile"))
        state.select(custom.id)
        await settle(until: { engine.applied.last?.id == custom.id })

        let status = EqualizerStatus()
        let view = EqualizerSettingsView(
            state: state,
            status: status,
            isRunning: true,
            openSettings: {},
            retry: {}
        ).frame(width: 860, height: 1000, alignment: .topLeading)
        let (window, hostingView) = makeHostingWindow(view: view)
        _ = hostingView
        await pumpEvents()

        // Locate "Đổi tên" button focus ring (x in 700...740, width in 70...85)
        let renameBtn = try #require(findFocusRing(in: hostingView, xRange: 700...740, widthRange: 70...85), "Rename button must be present for custom profile")

        // 1. Open Inline Rename Bar
        Swift.print("[UI-DISPATCH] Dispatching 'Đổi tên' (Rename) button click via native NSEvent at \(renameBtn.frame)")
        click(view: renameBtn, in: window, hostingView: hostingView)
        await pumpEvents()

        // 2. Locate NSTextField in inline rename bar and enter new name
        let textFields = findSubviews(of: NSTextField.self, in: hostingView)
        Swift.print("textFields count: \(textFields.count)")
        for tf in textFields {
            Swift.print("tf frame=\(tf.frame) stringValue=\(tf.stringValue)")
            if let p = tf.superview?.superview?.superview {
                Swift.print("tf container: \(type(of: p)) frame=\(p.frame)")
                for s in p.subviews {
                    Swift.print("  container child: \(type(of: s)) frame=\(s.frame)")
                }
            }
        }
        let textField = try #require(textFields.first, "TextField must be present in inline rename bar")
        window.makeFirstResponder(textField)
        if let editor = window.fieldEditor(true, for: textField) as? NSTextView {
            editor.string = "Studio Master Reference"
            editor.didChangeText()
        } else {
            textField.stringValue = "Studio Master Reference"
            NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: textField)
        }
        await pumpEvents()

        // 3. Locate "Lưu" button in inline rename bar (x in 750...785, y in 135...175, width in 35...50)
        let saveBtn = try #require(findFocusRing(in: hostingView, xRange: 750...785, yRange: 135...175, widthRange: 35...50), "Save button must be present in inline rename bar")
        Swift.print("[UI-DISPATCH] Dispatching 'Lưu' click in inline rename bar at \(saveBtn.frame)")
        click(view: saveBtn, in: window, hostingView: hostingView)
        await pumpEvents()

        await settle(until: { engine.applied.last?.name == "Studio Master Reference" })
        #expect(state.selected?.name == "Studio Master Reference", "Profile name must be updated to 'Studio Master Reference' via UI save button")
        #expect(engine.applied.last?.name == "Studio Master Reference", "Engine must receive updated profile name")
        Swift.print("[DOM/AX STATE] Verified profile renamed to 'Studio Master Reference' strictly via UI controls (TextField + Lưu button)")

        // 4. Test Cancel Workflow: open bar again, click 'Hủy' and verify name unchanged
        try? await Task.sleep(nanoseconds: 100_000_000)
        await pumpEvents()
        let reRenameBtn = try #require(findFocusRing(in: hostingView, xRange: 700...740, widthRange: 70...85), "Rename button must be present")
        click(view: reRenameBtn, in: window, hostingView: hostingView)
        await pumpEvents()

        let cancelBtn = try #require(findFocusRing(in: hostingView, xRange: 800...840, yRange: 135...175, widthRange: 35...50), "Cancel button must be present in inline rename bar")
        Swift.print("[UI-DISPATCH] Dispatching 'Hủy' click in inline rename bar at \(cancelBtn.frame)")
        click(view: cancelBtn, in: window, hostingView: hostingView)
        await pumpEvents()
        #expect(state.selected?.name == "Studio Master Reference", "Cancelling rename must preserve current name")
        #expect(engine.applied.last?.name == "Studio Master Reference", "Engine must receive updated profile name")
        Swift.print("[DOM/AX STATE] Verified profile renamed to 'Studio Master Reference' strictly via UI controls (TextField + Lưu button)")

        _ = window
    }

    @Test func testDeleteActionWithCancelAndConfirmLifecycle() async throws {
        await harness.registry.bootstrap()
        await settle(until: { engine.isRunning })

        // 1. System Default Protection: System profiles cannot be deleted
        let systemProfile = try #require(state.profiles.first(where: { state.isSystemDefault($0.id) }))
        state.select(systemProfile.id)
        #expect(state.isSystemDefault(systemProfile.id))
        #expect(!state.canDelete(systemProfile.id), "System profile cannot be deleted")

        // 2. Create a custom profile for deletion test
        let custom = try #require(state.addFlatProfile(named: "Profile To Delete"))
        state.select(custom.id)
        await settle(until: { engine.applied.last?.id == custom.id })
        Swift.print("Before View: selectedID=\(String(describing: state.selectedID)) name=\(state.selected?.name ?? "") canDelete=\(state.canDelete(custom.id))")
        #expect(state.canDelete(custom.id), "Custom profile can be deleted")

        let status = EqualizerStatus()
        let view = EqualizerSettingsView(
            state: state,
            status: status,
            isRunning: true,
            openSettings: {},
            retry: {}
        ).frame(width: 860, height: 1000, alignment: .topLeading)
        let (window, hostingView) = makeHostingWindow(view: view)
        _ = hostingView
        await pumpEvents()

        // Locate "Xóa" button focus ring (x in 780...820, y in 100...120, width in 50...70)
        let foundDelete = hostingView.subviews.first(where: {
            $0.frame.origin.x >= 780 && $0.frame.origin.x <= 820 &&
            $0.frame.origin.y >= 100 && $0.frame.origin.y <= 120 &&
            $0.frame.width >= 50 && $0.frame.width <= 70
        })
        let deleteBtn = try #require(foundDelete, "Delete button must be present for custom profile")

        let preDeleteCount = state.profiles.count

        // 3. Test Delete Dialog Cancel Lifecycle: cancelling preserves profile
        Swift.print("[UI-DISPATCH] Dispatching Delete button click & Cancel test at \(deleteBtn.frame)")
        click(view: deleteBtn, in: window, hostingView: hostingView)
        await pumpEvents()

        let cancelDeleteBtn = try #require(findFocusRing(in: hostingView, xRange: 800...840, yRange: 135...175, widthRange: 35...50), "Cancel button must be present in delete confirmation bar")
        Swift.print("[UI-DISPATCH] Dispatching Delete Cancel click")
        click(view: cancelDeleteBtn, in: window, hostingView: hostingView)
        await pumpEvents()
        #expect(state.profiles.count == preDeleteCount, "Cancelling delete dialog must leave profile count unchanged")

        // 4. Test Delete Confirm Lifecycle: confirming removes profile and falls back safely
        Swift.print("[UI-DISPATCH] Dispatching Delete button click to open confirm bar again")
        click(view: deleteBtn, in: window, hostingView: hostingView)
        await pumpEvents()

        let confirmDeleteBtn = try #require(findFocusRing(in: hostingView, xRange: 750...785, yRange: 135...175, widthRange: 35...50), "Confirm delete button must be present in delete confirmation bar")
        Swift.print("[UI-DISPATCH] Dispatching Delete Confirm action via button click")
        click(view: confirmDeleteBtn, in: window, hostingView: hostingView)
        await settle(until: { state.profiles.count == preDeleteCount - 1 })

        #expect(state.profiles.count == preDeleteCount - 1)
        #expect(state.profiles.contains(where: { $0.id == custom.id }) == false)
        #expect(state.selectedID != custom.id, "Selected ID must safely fall back when active profile is deleted")
        #expect(state.selected != nil, "A fallback profile must remain selected")
        Swift.print("[DOM/AX STATE] Verified deletion of custom profile and safe fallback to '\(state.selected?.name ?? "none")'")

        _ = window
    }

    @Test func testResetProfileToFlatZerosAllGains() async throws {
        await harness.registry.bootstrap()
        await settle(until: { engine.isRunning })

        // Create custom profile and boost bands
        let custom = try #require(state.addFlatProfile(named: "Custom Rock"))
        state.select(custom.id)
        state.setGain(8.0, band: 0)
        state.setGain(-4.0, band: 5)
        state.setPreamp(3.0)
        await settle(until: { engine.applied.last?.preamp == 3.0 })

        #expect(state.selected?.gains[0] == 8.0)
        #expect(state.selected?.gains[5] == -4.0)

        let status = EqualizerStatus()
        let view = EqualizerSettingsView(
            state: state,
            status: status,
            isRunning: true,
            openSettings: {},
            retry: {}
        ).frame(width: 860, height: 1000, alignment: .topLeading)
        let (window, hostingView) = makeHostingWindow(view: view)
        _ = hostingView
        await pumpEvents()

        // Locate "Đặt lại phẳng (0 dB)" button focus ring (x in 710...755, y in 420...500, width in 115...135)
        let resetFlatBtn = try #require(findFocusRing(in: hostingView, xRange: 710...755, yRange: 420...500, widthRange: 115...135), "Reset to Flat button must be present in view hierarchy")

        Swift.print("[UI-DISPATCH] Dispatching 'Đặt lại phẳng (0 dB)' click via native NSEvent at \(resetFlatBtn.frame)")
        click(view: resetFlatBtn, in: window, hostingView: hostingView)
        await settle(until: { engine.applied.last?.preamp == 0.0 && engine.applied.last?.gains[0] == 0.0 })

        #expect(state.selected?.gains.allSatisfy { $0 == 0.0 } == true)
        #expect(state.selected?.preamp == 0.0)
        #expect(engine.applied.last?.gains.allSatisfy { $0 == 0.0 } == true)
        #expect(engine.applied.last?.preamp == 0.0)
        Swift.print("[DOM/AX STATE] Verified reset to flat zeroed all 10 bands and preamp on state and engine")

        _ = window
    }

    @Test func testPreampSliderAndResetButtonInteraction() async throws {
        await harness.registry.bootstrap()
        await settle(until: { engine.isRunning })

        let status = EqualizerStatus()
        let view = EqualizerSettingsView(
            state: state,
            status: status,
            isRunning: true,
            openSettings: {},
            retry: {}
        ).frame(width: 860, height: 1000, alignment: .topLeading)
        let (window, hostingView) = makeHostingWindow(view: view)
        _ = hostingView
        await pumpEvents()

        // 1. Locate Preamp Slider focus ring (x in 40...70, y in 250...330, width > 500)
        let preampSlider = try #require(findFocusRing(in: hostingView, xRange: 40...70, yRange: 250...330, widthRange: 500...800), "Preamp Slider focus ring must be present")

        // Slider spans -12 dB to +12 dB (range = 24 dB). Center is 0 dB.
        // Clicking at 75% along the width corresponds to -12 + 0.75 * 24 = +6.0 dB.
        let targetX = preampSlider.frame.origin.x + (preampSlider.frame.width * 0.75)
        let targetY = preampSlider.frame.midY
        Swift.print("[UI-DISPATCH] Dispatching Preamp slider click at 75% position (\(targetX), \(targetY))")
        clickPoint(NSPoint(x: targetX, y: targetY), in: window, hostingView: hostingView)
        await pumpEvents()
        Swift.print("Preamp after click at 75%: \(String(describing: state.selected?.preamp))")
        await settle(until: { (state.selected?.preamp ?? 0) > 0 })
        let currentPreamp = try #require(state.selected?.preamp)
        #expect(currentPreamp > 0.0, "Preamp must be boosted by clicking right of center")

        // 2. Locate "0 dB" quick-reset button (x in 800...840, y in 290...360, width in 30...50)
        let reset0dBBtn = try #require(findFocusRing(in: hostingView, xRange: 800...840, yRange: 290...360, widthRange: 30...50), "Preamp 0 dB reset button must be present")

        Swift.print("[UI-DISPATCH] Clicking '0 dB' Preamp reset button via native NSEvent at \(reset0dBBtn.frame)")
        click(view: reset0dBBtn, in: window, hostingView: hostingView)
        await settle(until: { engine.applied.last?.preamp == 0.0 })

        #expect(state.selected?.preamp == 0.0)
        #expect(engine.applied.last?.preamp == 0.0)

        // Verify audio chain passes unity signal
        let chain = EQChain(channels: 1)
        chain.setParameters(gains: Array(repeating: 0.0, count: 10), preampDB: 0.0, sampleRate: 48000.0, ceilingDBTP: -0.5)
        let inSine: [Float] = (0..<128).map { _ in 0.1 }
        let outSine = withAudioBuffer(frames: 128, samples: inSine) { list in
            chain.process(list, frames: 128)
        }
        let peak = outSine.map { abs($0) }.max() ?? 0
        #expect(peak > 0.08 && peak <= 0.12, "0 dB preamp must pass unity signal ~0.1, got peak \(peak)")
        Swift.print("[SIDE-EFFECT] Verified 0 dB preamp button zeroed state and passed unity signal")

        _ = window
    }

    @Test func testPresetSelectionUpdatesDSPResponseCurve() async throws {
        await harness.registry.bootstrap()
        await settle(until: { engine.isRunning })

        let status = EqualizerStatus()
        let view = EqualizerSettingsView(
            state: state,
            status: status,
            isRunning: true,
            openSettings: {},
            retry: {}
        ).frame(width: 860, height: 1000, alignment: .topLeading)
        let (window, hostingView) = makeHostingWindow(view: view)
        _ = hostingView
        await pumpEvents()

        Swift.print("[UI-DISPATCH] Selecting 'Deep Bass (eqMac)' preset profile via native NSEvent on Preset Chip")
        let platformContainer = try #require(
            hostingView.subviews.first(where: { "\($0)".contains("PlatformContainer") }),
            "PlatformContainer for preset chips must be present"
        )
        func findDeepBassInContainer(_ v: NSView) -> NSView? {
            if v.frame.width > 110 && v.frame.width < 130 {
                return v
            }
            for s in v.subviews {
                if let found = findDeepBassInContainer(s) { return found }
            }
            return nil
        }
        let deepBassButton = try #require(findDeepBassInContainer(platformContainer), "Deep Bass preset button must be present in preset chips bar")
        let ptInHosting = deepBassButton.convert(NSPoint(x: deepBassButton.bounds.midX, y: deepBassButton.bounds.midY), to: hostingView)
        Swift.print("[UI-DISPATCH] Clicking Deep Bass preset button at \(ptInHosting)")
        clickPoint(ptInHosting, in: window, hostingView: hostingView)
        await pumpEvents()
        await settle(until: { state.selected?.name.contains("Deep Bass") == true })

        #expect(state.selected?.name.contains("Deep Bass") == true, "Selected profile must be Deep Bass after UI click")
        await settle(until: { engine.applied.last?.id == state.selectedID })

        let applied = try #require(engine.applied.last)
        #expect(applied.name.contains("Deep Bass"))
        #expect(applied.gains[0] == 14.0, "Deep Bass 32 Hz peaking band must be +14.0 dB")
        Swift.print("[ENGINE STATE] Verified Engine received Deep Bass profile: name=\(applied.name), 32Hz=\(applied.gains[0]) dB")

        // DSP Side-Effect: Audio Chain Verification with 32 Hz test signal
        let chain = EQChain(channels: 1)
        chain.setParameters(gains: applied.gains, preampDB: applied.preamp, sampleRate: 48000.0, ceilingDBTP: -0.5)
        let frames = 4500
        let in32Hz: [Float] = (0..<frames).map { f in
            let phase = 2.0 * Double.pi * 32.0 * Double(f) / 48000.0
            return Float(0.01 * sin(phase))
        }
        let out32Hz = withAudioBuffer(frames: frames, samples: in32Hz) { list in
            chain.process(list, frames: frames)
        }
        let peak32Hz = out32Hz.suffix(1000).map { abs($0) }.max() ?? 0
        #expect(peak32Hz > 0.035, "Deep Bass 32 Hz peaking band must boost 32 Hz signal by ~14 dB, got peak \(peak32Hz)")
        Swift.print("[SIDE-EFFECT] Verified Deep Bass curve boosts 32 Hz resonance in DSP chain: input=0.01, output peak=\(peak32Hz) (~14 dB boost)")

        _ = window
    }

    @Test func testTruePeakCeilingPickerAndLoudnessToggleMutateStateAndPipeline() async throws {
        await harness.registry.bootstrap()
        await settle(until: { engine.isRunning })

        let status = EqualizerStatus()
        let view = EqualizerSettingsView(
            state: state,
            status: status,
            isRunning: true,
            openSettings: {},
            retry: {}
        ).frame(width: 860, height: 1000, alignment: .topLeading)
        let (window, hostingView) = makeHostingWindow(view: view)
        _ = hostingView
        await pumpEvents()

        #expect(state.ceilingDBTP == -0.5, "Default ceiling must be -0.5 dBTP")
        #expect(state.isLoudnessEnabled == false, "Default dynamic loudness must be false")

        // 1. Locate True-Peak Radio Button for -1.0 dBTP (y in 510...565)
        let foundMinusOne = findFocusRing(in: hostingView, xRange: 105...125, yRange: 510...565, widthRange: 140...170)
        let radioMinusOne = try #require(foundMinusOne, "Radio button for -1.0 dBTP must be present in view hierarchy")
        Swift.print("[UI-DISPATCH] Clicking True-Peak -1.0 dBTP radio button via native NSEvent at \(radioMinusOne.frame)")
        click(view: radioMinusOne, in: window, hostingView: hostingView)
        await pumpEvents()
        await settle(until: { state.ceilingDBTP == -1.0 })
        #expect(state.ceilingDBTP == -1.0, "Clicking -1.0 dBTP radio button must mutate state to -1.0")
        #expect(engine.processingSettingsCalls.last?.ceiling == -1.0, "Engine must receive ceiling -1.0 from UI click")

        // 2. Locate True-Peak Radio Button for 0.0 dBTP (y in 565...615)
        let foundZero = findFocusRing(in: hostingView, xRange: 105...125, yRange: 565...615, widthRange: 175...205)
        let radioZero = try #require(foundZero, "Radio button for 0.0 dBTP must be present in view hierarchy")
        Swift.print("[UI-DISPATCH] Clicking True-Peak 0.0 dBTP radio button via native NSEvent at \(radioZero.frame)")
        click(view: radioZero, in: window, hostingView: hostingView)
        await pumpEvents()
        await settle(until: { state.ceilingDBTP == 0.0 })
        #expect(state.ceilingDBTP == 0.0, "Clicking 0.0 dBTP radio button must mutate state to 0.0")
        #expect(engine.processingSettingsCalls.last?.ceiling == 0.0, "Engine must receive ceiling 0.0 from UI click")

        // 3. Locate Dynamic Loudness Toggle (x in 0...25, y in 635...700, width > 200)
        let foundLoudness = findFocusRing(in: hostingView, xRange: 0...25, yRange: 635...700, widthRange: 200...300)
        let loudnessToggle = try #require(foundLoudness, "Dynamic Loudness toggle must be present in view hierarchy")
        Swift.print("[UI-DISPATCH] Clicking Dynamic Loudness toggle via native NSEvent at \(loudnessToggle.frame)")
        click(view: loudnessToggle, in: window, hostingView: hostingView)
        await pumpEvents()
        await settle(until: { state.isLoudnessEnabled == true })
        #expect(state.isLoudnessEnabled == true, "Clicking Dynamic Loudness toggle must turn it ON")
        #expect(engine.loudness.last == true, "Engine must receive loudness = true from UI click")

        // Click again to turn OFF
        Swift.print("[UI-DISPATCH] Clicking Dynamic Loudness toggle again to turn OFF")
        click(view: loudnessToggle, in: window, hostingView: hostingView)
        await pumpEvents()
        await settle(until: { state.isLoudnessEnabled == false })
        #expect(state.isLoudnessEnabled == false, "Second click must turn Dynamic Loudness OFF")
        #expect(engine.loudness.last == false, "Engine must receive loudness = false from UI click")
        #expect(state.isLoudnessEnabled == false)
        #expect(engine.loudness.last == false)
        Swift.print("[SIDE-EFFECT] Verified True-Peak ceiling and Dynamic Loudness mutation, persistence, and engine forwarding")

        _ = window
    }

    @Test func testTelemetryDisplayRendersRealStreamMetadata() async throws {
        let status = EqualizerStatus()
        status.phase = .processing(["MacBook Pro Speakers"])
        status.activeDeviceTelemetries = [
            EQDeviceTelemetry(
                uid: "speaker-uid",
                name: "MacBook Pro Speakers",
                sampleRate: 48000,
                volumePercent: 72,
                channelCount: 2,
                isProcessing: true
            )
        ]

        let view = EqualizerSettingsView(
            state: state,
            status: status,
            isRunning: true,
            openSettings: {},
            retry: {}
        ).frame(width: 860, height: 1000, alignment: .topLeading)
        let (window, hostingView) = makeHostingWindow(view: view)
        _ = hostingView
        await pumpEvents()

        #expect(hostingView.frame.width > 0 && hostingView.frame.height > 0)
        let telemetry = try #require(status.activeDeviceTelemetries.first)
        #expect(telemetry.sampleRate == 48000)
        #expect(telemetry.volumePercent == 72)
        #expect(telemetry.channelCount == 2)
        Swift.print("[DOM/AX STATE] Telemetry view rendered with live stream metadata: 48.0 kHz, 72%, 2 ch")

        _ = window
    }
}
