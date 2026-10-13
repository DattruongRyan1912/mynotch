import Foundation
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct HotkeyRegistryTests {
    static let controlOptionV = KeyboardShortcuts.Shortcut(.v, modifiers: [.control, .option])
    static let controlOptionT = KeyboardShortcuts.Shortcut(.t, modifiers: [.control, .option])

    let backend = FakeHotkeyBackend()
    let registry: HotkeyRegistry

    init() {
        registry = HotkeyRegistry(backend: backend)
    }

    @Test func namesAreScopedByOwner() {
        #expect(HotkeyRegistry.qualifiedName("toggleNotch", owner: nil) == "app_toggleNotch")
        #expect(HotkeyRegistry.qualifiedName("openTab", owner: "battery") == "battery_openTab")
    }

    @Test func registerAssignsTheInitialShortcutAndRunsTheActionOnPress() throws {
        var presses = 0
        registry.register("openTab", title: "Open", owner: "battery", initial: Self.controlOptionV) { presses += 1 }
        let registration = try #require(registry.registrations.first)
        #expect(registration.id == "battery_openTab")
        #expect(backend.getShortcut(for: registration.name) == Self.controlOptionV)
        #expect(backend.trigger("battery_openTab"))
        #expect(presses == 1)
    }

    @Test func registeringAgainReplacesTheAction() {
        var log: [String] = []
        registry.register("openTab", title: "Open", owner: "battery") { log.append("old") }
        registry.register("openTab", title: "Open again", owner: "battery") { log.append("new") }
        #expect(registry.registrations.map(\.title) == ["Open again"])
        backend.trigger("battery_openTab")
        #expect(log == ["new"])
    }

    @Test func aShortcutTheUserChangedSurvivesRegisteringAgain() throws {
        registry.register("openTab", title: "Open", owner: "battery", initial: Self.controlOptionV) {}
        let name = try #require(registry.registrations.first).name
        #expect(backend.getShortcut(for: name) == Self.controlOptionV)
        backend.setShortcut(Self.controlOptionT, for: name)
        registry.register("openTab", title: "Open", owner: "battery", initial: Self.controlOptionV) {}
        #expect(backend.getShortcut(for: name) == Self.controlOptionT)
        backend.setShortcut(nil, for: name)
        registry.register("openTab", title: "Open", owner: "battery", initial: Self.controlOptionV) {}
        #expect(backend.getShortcut(for: name) == nil)
    }

    @Test func conflictsGroupRegistrationsSharingAKeyCombination() throws {
        registry.register("b", title: "B", owner: "two", initial: Self.controlOptionV) {}
        registry.register("a", title: "A", owner: "one", initial: Self.controlOptionV) {}
        registry.register("c", title: "C", owner: "three", initial: Self.controlOptionT) {}
        registry.register("d", title: "D", owner: "four") {}
        #expect(registry.conflicts().map { $0.map(\.id) } == [["one_a", "two_b"]])

        let b = try #require(registry.registrations.first { $0.id == "two_b" })
        backend.setShortcut(Self.controlOptionT, for: b.name)
        #expect(registry.conflicts().map { $0.map(\.id) } == [["three_c", "two_b"]])
        backend.setShortcut(nil, for: b.name)
        #expect(registry.conflicts().isEmpty)
    }

    @Test func invalidatedModuleHotkeysUnregisterAndIgnoreLateRegistrations() {
        var presses = 0
        let hotkeys = ModuleHotkeys(registry: registry, module: "battery")
        hotkeys.register("openTab", title: "Open") { presses += 1 }
        #expect(registry.registrations.map(\.id) == ["battery_openTab"])
        hotkeys.invalidate()
        #expect(registry.registrations.isEmpty)
        #expect(!backend.trigger("battery_openTab"))
        hotkeys.register("late", title: "Late") { presses += 1 }
        #expect(registry.registrations.isEmpty)
        #expect(!backend.trigger("battery_late"))
        #expect(presses == 0)
    }

    @Test func harnessShortcutsNeverReachKeyboardShortcuts() throws {
        let harness = RegistryHarness([])
        let localName = "probe\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        harness.hotkeys.register(localName, title: "Probe", owner: nil, initial: Self.controlOptionV) {}
        let name = try #require(harness.hotkeys.registrations.first).name
        #expect(harness.hotkeyBackend.getShortcut(for: name) == Self.controlOptionV)
        #expect(KeyboardShortcuts.getShortcut(for: name) == nil)
    }
}
