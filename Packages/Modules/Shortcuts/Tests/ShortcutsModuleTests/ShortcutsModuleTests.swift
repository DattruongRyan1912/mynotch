import AppKit
import KeyboardShortcuts
import MyNotchCore
import MyNotchTestSupport
import Observation
import Synchronization
import Testing
@testable import ShortcutsModule

private let alpha = ShortcutInfo(id: "AAAAAAAA-1111-2222-3333-444444444444", name: "Alpha")
private let beta = ShortcutInfo(id: "BBBBBBBB-1111-2222-3333-444444444444", name: "Beta")

/// A module wired to fakes: no process, no global hotkey, no real pasteboard.
struct ShortcutsFixture {
    let cli = FakeShortcutsCLI()
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("MyNotchTests.\(UUID().uuidString)"))
    let module: ShortcutsModule
    let harness: RegistryHarness

    init(shortcuts: [ShortcutInfo] = [alpha, beta]) {
        cli.listing = .success(shortcuts)
        module = ShortcutsModule(cli: cli, pasteboard: pasteboard)
        harness = RegistryHarness([module])
    }

    var settings: ModuleSettings { harness.settingsEnvironment(for: "shortcuts")!.settings }
    var keys: ShortcutsSettingKeys { ShortcutsSettingKeys(settings) }
    var favorites: [String] {
        get { settings.value(keys.favorites) }
        nonmutating set { settings.set(newValue, for: keys.favorites) }
    }

    func start() async {
        await harness.registry.bootstrap()
    }
}

@Suite struct ShortcutsModuleTests {
    let fixture = ShortcutsFixture()
    var module: ShortcutsModule { fixture.module }

    @Test func describesItself() {
        let descriptor = module.descriptor
        #expect(descriptor.id == "shortcuts")
        #expect(descriptor.displayName == "Shortcuts")
        #expect(descriptor.systemImage == "square.stack.3d.up")
        #expect(descriptor.order == 850)
        #expect(descriptor.permissions.isEmpty)
    }

    @Test func tabIsShortcutsAt150() async {
        await fixture.start()
        #expect(fixture.harness.registry.state(of: "shortcuts") == .running)
        let tab = module.makeTab()
        #expect(tab?.title == "Shortcuts")
        #expect(tab?.preferredHeight == 150)
    }

    // MARK: Favourites

    @Test func favouritesStartEmptyAndPersistAsIdentifiers() {
        #expect(fixture.favorites.isEmpty)
        fixture.favorites = [beta.id, alpha.id]
        #expect(fixture.favorites == [beta.id, alpha.id])
        #expect(fixture.settings.value(fixture.keys.favorites) == [beta.id, alpha.id])
        #expect(fixture.keys.favorites.name == "module.shortcuts.favorites")
    }

    @Test func togglingAFavouriteKeepsTheOrderAndNeverDuplicates() {
        #expect(ShortcutFavorites.setting("a", isFavorite: true, in: []) == ["a"])
        #expect(ShortcutFavorites.setting("b", isFavorite: true, in: ["a"]) == ["a", "b"])
        #expect(ShortcutFavorites.setting("a", isFavorite: true, in: ["a", "b"]) == ["a", "b"])
        #expect(ShortcutFavorites.setting("a", isFavorite: false, in: ["a", "b"]) == ["b"])
        #expect(ShortcutFavorites.setting("z", isFavorite: false, in: ["a"]) == ["a"])
    }

    @Test func theTabShowsTheFavouritesThatStillExist() async {
        fixture.favorites = [beta.id, "gone", alpha.id]
        await fixture.start()
        await module.refresh()
        #expect(module.favoriteShortcuts == [beta, alpha])
    }

    // MARK: List

    @Test func refreshCachesTheList() async {
        await module.refresh()
        #expect(module.state.shortcuts == [alpha, beta])
        #expect(module.state.listError == nil)
        #expect(!module.state.isLoading)
    }

    @Test func aFailedRefreshKeepsTheCachedListAndReportsTheError() async {
        await module.refresh()
        fixture.cli.listing = .failure(ShortcutsCLIError.failed("nope"))
        await module.refresh()
        #expect(module.state.shortcuts == [alpha, beta])
        #expect(module.state.listError == "nope")
        #expect(!module.state.isLoading)
    }

    @Test func startingListsTheShortcutsOnlyWhenThereAreFavouritesToName() async {
        await fixture.start()
        try? await Task.sleep(for: .milliseconds(60))
        #expect(fixture.cli.listCount == 0)

        let withFavourites = ShortcutsFixture()
        withFavourites.favorites = [alpha.id]
        await withFavourites.start()
        await settle { withFavourites.cli.listCount == 1 }
        #expect(withFavourites.cli.listCount == 1)
    }

    // MARK: Hotkeys

    @Test func registersAHotkeyPerFavourite() async {
        fixture.favorites = [alpha.id, beta.id]
        await fixture.start()
        let registrations = fixture.harness.hotkeys.registrations
        #expect(Set(registrations.map(\.id)) == [
            "shortcuts_run_AAAAAAAA_1111_2222_3333_444444444444",
            "shortcuts_run_BBBBBBBB_1111_2222_3333_444444444444",
        ])
        #expect(registrations.allSatisfy { $0.owner == "shortcuts" })
        // None has a key combination until the user records one.
        #expect(fixture.harness.hotkeyBackend.getShortcut(for: registrations[0].name) == nil)
    }

    @Test func pressingAFavouritesHotkeyRunsIt() async {
        fixture.favorites = [alpha.id]
        await fixture.start()
        #expect(fixture.harness.hotkeyBackend.trigger("shortcuts_run_AAAAAAAA_1111_2222_3333_444444444444"))
        await settle { fixture.cli.ran == [alpha.id] }
        #expect(fixture.cli.ran == [alpha.id])
    }

    @Test func addingAFavouriteWhileRunningRegistersItsHotkey() async {
        await fixture.start()
        #expect(fixture.harness.hotkeys.registrations.isEmpty)
        fixture.favorites = [beta.id]
        await settle { !fixture.harness.hotkeys.registrations.isEmpty }
        #expect(fixture.harness.hotkeys.registrations.map(\.id) == ["shortcuts_run_BBBBBBBB_1111_2222_3333_444444444444"])
        // A second change is seen too.
        fixture.favorites = [beta.id, alpha.id]
        await settle { fixture.harness.hotkeys.registrations.count == 2 }
        #expect(fixture.harness.hotkeys.registrations.count == 2)
    }

    @Test func aHotkeyOfAShortcutThatIsNoLongerFavouriteDoesNothing() async {
        fixture.favorites = [alpha.id]
        await fixture.start()
        fixture.favorites = []
        fixture.harness.hotkeyBackend.trigger("shortcuts_run_AAAAAAAA_1111_2222_3333_444444444444")
        try? await Task.sleep(for: .milliseconds(60))
        #expect(fixture.cli.ran.isEmpty)
    }

    @Test func hotkeysTitleTheShortcutByNameOnceTheListIsKnown() async {
        fixture.favorites = [alpha.id]
        await fixture.start()
        await settle { fixture.harness.hotkeys.registrations.first?.title == "Chạy Alpha" }
        #expect(fixture.harness.hotkeys.registrations.first?.title == "Chạy Alpha")
    }

    @Test func refreshingAgainLeavesTheRegisteredHotkeysAlone() async {
        fixture.favorites = [alpha.id, beta.id]
        await fixture.start()
        await settle { Set(fixture.harness.hotkeys.registrations.map(\.title)) == ["Chạy Alpha", "Chạy Beta"] }
        let changed = Mutex(false)
        withObservationTracking {
            _ = fixture.harness.hotkeys.registrations
        } onChange: {
            changed.withLock { $0 = true }
        }
        await module.refresh()
        #expect(!changed.withLock { $0 })
    }

    @Test func stoppingRemovesTheHotkeys() async {
        fixture.favorites = [alpha.id]
        await fixture.start()
        await fixture.harness.registry.setEnabled(false, for: "shortcuts")
        #expect(fixture.harness.hotkeys.registrations.isEmpty)
    }

    @Test func hotkeyNamesHaveNoDots() {
        #expect(ShortcutFavorites.hotkeyName(for: "a.b-c d/é") == "run_a_b_c_d__")
    }

    // MARK: Running

    @Test func runningShowsASpinnerThenAnActivity() async {
        await fixture.start()
        fixture.cli.isGated = true
        await module.refresh()
        module.run(alpha.id)
        #expect(module.state.running == [alpha.id])
        // The same shortcut is not started twice.
        module.run(alpha.id)
        await settle { fixture.cli.ran == [alpha.id] }
        fixture.cli.release()
        await settle { module.state.running.isEmpty }
        #expect(fixture.cli.ran == [alpha.id])
        #expect(module.state.lastResult == .ran(name: "Alpha"))
        #expect(module.state.lastResult?.text == "Đã chạy Alpha")
        #expect(fixture.harness.activities.current?.id == "shortcuts/result")
        #expect(fixture.harness.presenter.toastCount == 0)
    }

    @Test func aFailedRunReportsTheError() async {
        await fixture.start()
        fixture.cli.outputs[alpha.id] = .failure(ShortcutsCLIError.failed("Không tìm thấy"))
        await module.refresh()
        module.run(alpha.id)
        await settle { module.state.lastResult != nil }
        #expect(module.state.lastResult == .failed(message: "Không tìm thấy"))
        #expect(module.state.lastResult?.text == "Lỗi: Không tìm thấy")
        #expect(module.state.running.isEmpty)
        #expect(fixture.harness.activities.current?.id == "shortcuts/result")
    }

    @Test func aTimeoutHasItsOwnMessage() async {
        await fixture.start()
        fixture.cli.outputs[alpha.id] = .failure(ShortcutsCLIError.timedOut)
        module.run(alpha.id)
        await settle { module.state.lastResult != nil }
        #expect(module.state.lastResult == .failed(message: "quá 60 giây"))
    }

    @Test func textOutputShowsAToastAndCopies() async {
        await fixture.start()
        fixture.cli.outputs[alpha.id] = .success("Kết quả")
        await module.refresh()
        module.run(alpha.id)
        await settle { fixture.harness.presenter.toastCount == 1 }
        #expect(fixture.harness.presenter.toastCount == 1)
        #expect(module.state.lastResult == .ran(name: "Alpha"))

        module.copy("Kết quả")
        #expect(fixture.pasteboard.string(forType: .string) == "Kết quả")
    }

    @Test func stoppingWhileRunningLeavesNoResult() async {
        await fixture.start()
        fixture.cli.isGated = true
        module.run(alpha.id)
        await settle { fixture.cli.ran == [alpha.id] }
        await fixture.harness.registry.setEnabled(false, for: "shortcuts")
        fixture.cli.release()
        try? await Task.sleep(for: .milliseconds(60))
        #expect(module.state.running.isEmpty)
        #expect(module.state.lastResult == nil)
        #expect(fixture.harness.activities.current == nil)
    }

    // MARK: Output toast

    @Test func theToastShowsOnlyTheStartOfALongOutput() {
        #expect(ShortcutOutputToast.preview(of: "ngắn") == "ngắn")
        let exact = String(repeating: "a", count: ShortcutOutputToast.previewLimit)
        #expect(ShortcutOutputToast.preview(of: exact) == exact)
        let long = String(repeating: "é", count: 64 * 1024)
        #expect(ShortcutOutputToast.preview(of: long) == String(repeating: "é", count: ShortcutOutputToast.previewLimit) + "…")
    }
}
