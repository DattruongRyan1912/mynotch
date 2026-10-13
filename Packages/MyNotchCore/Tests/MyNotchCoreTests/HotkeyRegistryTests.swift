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

    @Test func unregisteringByNameRemovesTheRegistrationAndTheHandler() {
        var presses = 0
        registry.register("openTab", title: "Open", owner: "battery") { presses += 1 }
        registry.register("other", title: "Other", owner: "battery") { presses += 10 }
        registry.unregister("openTab", owner: "battery")
        #expect(registry.registrations.map(\.id) == ["battery_other"])
        #expect(!backend.trigger("battery_openTab"))
        #expect(presses == 0)
        #expect(backend.trigger("battery_other"))
        #expect(presses == 10)
    }

    @Test func unregisteringOneNameLeavesTheSameNameOfOtherOwnersAlone() {
        var log: [String] = []
        registry.register("open", title: "Battery", owner: "battery") { log.append("battery") }
        registry.register("open", title: "Clipboard", owner: "clipboard") { log.append("clipboard") }
        registry.register("open", title: "App", owner: nil) { log.append("app") }
        registry.unregister("open", owner: "battery")
        #expect(Set(registry.registrations.map(\.id)) == ["clipboard_open", "app_open"])
        #expect(!backend.trigger("battery_open"))
        backend.trigger("clipboard_open")
        backend.trigger("app_open")
        #expect(log == ["clipboard", "app"])
        registry.unregister("open", owner: nil)
        #expect(registry.registrations.map(\.id) == ["clipboard_open"])
    }

    @Test func unregisteringANameThatWasNeverRegisteredDoesNothing() {
        registry.register("openTab", title: "Open", owner: "battery") {}
        registry.unregister("missing", owner: "battery")
        registry.unregister("openTab", owner: "clipboard")
        #expect(registry.registrations.map(\.id) == ["battery_openTab"])
        #expect(backend.trigger("battery_openTab"))
    }

    @Test func aModuleUnregistersOneOfItsHotkeysAndCanRegisterItAgain() {
        var presses = 0
        let hotkeys = ModuleHotkeys(registry: registry, module: "battery")
        let other = ModuleHotkeys(registry: registry, module: "clipboard")
        hotkeys.register("openTab", title: "Open") { presses += 1 }
        hotkeys.register("keep", title: "Keep") { presses += 10 }
        other.register("openTab", title: "Other module") { presses += 100 }
        hotkeys.unregister("openTab")
        #expect(Set(registry.registrations.map(\.id)) == ["battery_keep", "clipboard_openTab"])
        #expect(!backend.trigger("battery_openTab"))
        #expect(presses == 0)
        hotkeys.register("openTab", title: "Open") { presses += 1 }
        #expect(backend.trigger("battery_openTab"))
        #expect(presses == 1)
    }

    @Test func unregisteringByNameIsInertOnceTheModuleStopped() {
        let hotkeys = ModuleHotkeys(registry: registry, module: "battery")
        hotkeys.register("openTab", title: "Open") {}
        hotkeys.invalidate()
        // The same name now belongs to a module that started again; the stopped facade must not touch it.
        let restarted = ModuleHotkeys(registry: registry, module: "battery")
        restarted.register("openTab", title: "Open") {}
        hotkeys.unregister("openTab")
        #expect(registry.registrations.map(\.id) == ["battery_openTab"])
        #expect(backend.trigger("battery_openTab"))
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
