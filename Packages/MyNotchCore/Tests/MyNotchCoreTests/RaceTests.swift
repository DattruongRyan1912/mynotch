import SwiftUI
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

/// Suspends callers until opened.
final class Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var waiting: Int { waiters.count }
    func wait() async { await withCheckedContinuation { waiters.append($0) } }
    func open() { let w = waiters; waiters.removeAll(); w.forEach { $0.resume() } }
    func untilWaiting(_ n: Int = 1) async { while waiters.count < n { await Task.yield() } }
}

final class GatedModule: FeatureModule {
    let descriptor: ModuleDescriptor
    var gateStart = false
    var gateStop = false
    let startGate = Gate()
    let stopGate = Gate()
    var startErrors: [ModuleError?] = []
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var inFlight = 0
    private(set) var maxInFlight = 0
    private(set) var internallyRunning = false

    init(_ id: ModuleID, order: Int = 0) {
        descriptor = ModuleDescriptor(id: id, displayName: id.rawValue, systemImage: "circle", defaultEnabled: true, order: order)
    }

    func start(_ context: ModuleContext) async throws(ModuleError) {
        startCount += 1
        inFlight += 1; maxInFlight = max(maxInFlight, inFlight)
        defer { inFlight -= 1 }
        if gateStart { await startGate.wait() }
        let error = startErrors.isEmpty ? nil : startErrors.removeFirst()
        if let error { throw error }
        context.activities.set(activity("live"))
        internallyRunning = true
    }

    func stop() async {
        stopCount += 1
        inFlight += 1; maxInFlight = max(maxInFlight, inFlight)
        defer { inFlight -= 1 }
        if gateStop { await stopGate.wait() }
        internallyRunning = false
    }

    func makeTab() -> NotchTab? { NotchTab(id: descriptor.id, title: "t", systemImage: "circle", content: AnyView(EmptyView())) }
    func makeSettingsView() -> AnyView? { nil }
}

@Suite struct RaceTests {
    @Test func disableWhileStarting() async {
        let m = GatedModule("m"); m.gateStart = true
        let h = RegistryHarness([m])
        let boot = Task { await h.registry.bootstrap() }
        await m.startGate.untilWaiting()
        let off = Task { await h.registry.setEnabled(false, for: "m") }
        for _ in 0..<20 { await Task.yield() }
        m.startGate.open()
        await boot.value; await off.value
        #expect(h.registry.state(of: "m") == .disabled)
        #expect(h.registry.tabs.isEmpty)
        #expect(!m.internallyRunning)
    }

    @Test func reenableWhileStopping() async {
        let m = GatedModule("m")
        let h = RegistryHarness([m])
        await h.registry.bootstrap()
        m.gateStop = true
        let off = Task { await h.registry.setEnabled(false, for: "m") }
        await m.stopGate.untilWaiting()
        let on = Task { await h.registry.setEnabled(true, for: "m") }
        for _ in 0..<20 { await Task.yield() }
        m.stopGate.open()
        await off.value; await on.value
        #expect(h.registry.state(of: "m") == .running)
        #expect(h.activities.entries.count == 1)
        #expect(m.maxInFlight == 1)
    }

    @Test func pauseDuringBootstrap() async {
        let a = GatedModule("a", order: 1); a.gateStart = true
        let b = GatedModule("b", order: 2)
        let h = RegistryHarness([a, b])
        let boot = Task { await h.registry.bootstrap() }
        await a.startGate.untilWaiting()
        let pause = Task { await h.registry.pauseAll() }
        for _ in 0..<20 { await Task.yield() }
        a.startGate.open()
        await boot.value; await pause.value
        #expect(h.registry.state(of: "a") == .disabled)
        #expect(h.registry.state(of: "b") == .disabled)
        #expect(!b.internallyRunning)
    }

    @Test func staleFailedStartTearsDownNewerContext() async {
        let m = GatedModule("m"); m.gateStart = true
        m.startErrors = [.failed(reason: "first"), nil]
        let h = RegistryHarness([m])
        let boot = Task { await h.registry.bootstrap() }
        await m.startGate.untilWaiting()
        let off = Task { await h.registry.setEnabled(false, for: "m") }
        for _ in 0..<20 { await Task.yield() }
        let on = Task { await h.registry.setEnabled(true, for: "m") }
        for _ in 0..<20 { await Task.yield() }
        m.startGate.open()
        for _ in 0..<50 where m.startGate.waiting == 0 { await Task.yield() }  // second start (if serialized)
        m.startGate.open()
        await boot.value; await off.value; await on.value
        #expect(m.maxInFlight == 1)
        #expect(h.registry.state(of: "m") == .running)
        #expect(h.activities.entries.count == 1)
    }

    @Test func resumeWhilePausing() async {
        let m = GatedModule("m")
        let h = RegistryHarness([m])
        await h.registry.bootstrap()
        m.gateStop = true
        let pause = Task { await h.registry.pauseAll() }
        await m.stopGate.untilWaiting()
        // user un-pauses quickly via menu
        let resume = Task { await h.registry.resumeAll() }
        for _ in 0..<20 { await Task.yield() }
        m.stopGate.open()
        await pause.value; await resume.value
        #expect(h.registry.state(of: "m") == .running)
        #expect(h.activities.entries.count == 1)
    }
}

@Suite struct IsolationTests {
    @Test func slowStartDoesNotHoldUpOtherModules() async {
        let slow = GatedModule("slow", order: 1); slow.gateStart = true
        let fast = GatedModule("fast", order: 2)
        let h = RegistryHarness([slow, fast])
        let boot = Task { await h.registry.bootstrap() }
        await slow.startGate.untilWaiting()
        for _ in 0..<20 { await Task.yield() }
        #expect(h.registry.state(of: "fast") == .running)
        slow.startGate.open()
        await boot.value
    }
}
