import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct MenuBarHiderShortcutTests {
    private let backend = FakeHotkeyBackend()
    private let controlOptionN = KeyboardShortcuts.Shortcut(.n, modifiers: [.control, .option])

    private func makeRegistry(onCollision: @escaping (HotkeyRegistry.Registration, HotkeyRegistry.Registration) -> Void = { _, _ in }) -> HotkeyRegistry {
        HotkeyRegistry(backend: backend, onDefaultCollision: onCollision)
    }

    @Test func theNameIsFixedSoTheKeyTheUserRecordedSurvives() {
        #expect(MenuBarHiderShortcut.name == "toggleMenuBarIcons")
        let registry = makeRegistry()
        MenuBarHiderShortcut.register(in: registry) {}
        #expect(registry.registrations.map(\.id) == ["app_toggleMenuBarIcons"])
        #expect(registry.registrations.first?.title == "Hiện/ẩn icon menu bar")
    }

    @Test func hasNoDefaultKey() throws {
        let registry = makeRegistry()
        MenuBarHiderShortcut.register(in: registry) {}
        let registration = try #require(registry.registrations.first)
        #expect(registration.defaultShortcut == nil)
        #expect(backend.getShortcut(for: registration.name) == nil)
    }

    @Test func pressingTheKeyTogglesTheHider() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let hider = MenuBarHider(settings: settings, scheduler: ManualScheduler())
        hider.attach(FakeSeparator())
        let registry = makeRegistry()
        MenuBarHiderShortcut.register(in: registry) { hider.toggle() }
        #expect(backend.trigger("app_toggleMenuBarIcons"))
        #expect(hider.isCollapsed)
        #expect(backend.trigger("app_toggleMenuBarIcons"))
        #expect(!hider.isCollapsed)
    }

    @Test func aRefusedHideLeavesTheKeyHarmless() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let hider = MenuBarHider(settings: settings, scheduler: ManualScheduler())
        let separator = FakeSeparator()
        separator.dragSeparatorRightOfToggle()
        hider.attach(separator)
        let registry = makeRegistry()
        MenuBarHiderShortcut.register(in: registry) { hider.toggle() }
        #expect(backend.trigger("app_toggleMenuBarIcons"))
        #expect(!hider.isCollapsed)
    }

    @Test func registeringBesideTheNotchShortcutIsNoCollision() {
        var collisions = 0
        let registry = makeRegistry { _, _ in collisions += 1 }
        registry.register("toggleNotch", title: "Mở/đóng notch", owner: nil, initial: controlOptionN) {}
        MenuBarHiderShortcut.register(in: registry) {}
        #expect(collisions == 0)
        #expect(registry.conflicts().isEmpty)
    }

    @Test func theRegistryListsItWhenTheUserGivesItAnotherShortcutsKey() throws {
        let registry = makeRegistry()
        registry.register("toggleNotch", title: "Mở/đóng notch", owner: nil, initial: controlOptionN) {}
        MenuBarHiderShortcut.register(in: registry) {}
        let name = try #require(registry.registrations.first { $0.id == "app_toggleMenuBarIcons" }).name
        backend.setShortcut(controlOptionN, for: name)
        let conflicts = registry.conflicts()
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.map(\.id) == ["app_toggleMenuBarIcons", "app_toggleNotch"])
    }
}
