import AppKit
import MyNotchCore
import Observation
import SwiftUI

/// Runs favourite Apple Shortcuts from the notch: a button each in the tab, and an optional global hotkey each.
/// Results show beside the closed notch; text a shortcut returns comes up as a toast that can be copied.
public final class ShortcutsModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "shortcuts",
        displayName: "Shortcuts",
        systemImage: "square.stack.3d.up",
        defaultEnabled: true,
        order: 850
    )

    static let resultActivityID = "result"

    let state = ShortcutsState()
    private let cli: any ShortcutsCLI
    private let pasteboard: NSPasteboard
    private var context: ModuleContext?
    private var keys: ShortcutsSettingKeys?
    private var isListing = false
    /// Title of the hotkey registered for each favourite, so a refresh registers again only what changed.
    private var hotkeyTitles: [String: String] = [:]

    public convenience init() {
        self.init(cli: SystemShortcutsCLI(), pasteboard: .general)
    }

    /// Tests pass a fake CLI and a private pasteboard, so they never run `shortcuts` or touch the system clipboard.
    init(cli: any ShortcutsCLI, pasteboard: NSPasteboard) {
        self.cli = cli
        self.pasteboard = pasteboard
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        self.context = context
        let keys = ShortcutsSettingKeys(context.settings)
        self.keys = keys
        hotkeyTitles = [:]
        syncHotkeys()
        observeFavorites(context)
        // The list names the favourites (hotkey titles, "Đã chạy X"); without any, the tab and Settings load it when opened.
        if !context.settings.value(keys.favorites).isEmpty {
            context.run { [weak self] in await self?.refresh() }
        }
    }

    public func stop() async {
        context = nil
        keys = nil
        state.running = []
        state.lastResult = nil
    }

    public func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id, title: "Shortcuts", systemImage: "square.stack.3d.up",
            preferredHeight: 150, content: AnyView(ShortcutsTabView(module: self))
        )
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        AnyView(ShortcutsSettingsView(module: self, settings: environment.settings, keys: ShortcutsSettingKeys(environment.settings)))
    }

    // MARK: List

    /// Asks the CLI for the list again. Without a running module it still works, for the Settings rows.
    func refresh() async {
        guard !isListing else { return }
        isListing = true
        state.isLoading = true
        defer {
            isListing = false
            state.isLoading = false
        }
        do {
            state.shortcuts = try await cli.list()
            state.listError = nil
            syncHotkeys()
        } catch is CancellationError {
            return
        } catch {
            state.listError = Self.message(for: error)
        }
    }

    /// The favourites the list still has, in the order the user picked them.
    var favoriteShortcuts: [ShortcutInfo] {
        guard let context, let keys else { return [] }
        let byID = Dictionary(state.shortcuts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return context.settings.value(keys.favorites).compactMap { byID[$0] }
    }

    // MARK: Hotkeys

    /// One hotkey per favourite. Registering again replaces the handler and keeps the key the user recorded, so
    /// a hotkey is registered again only when its title changes, which happens once the list gives the shortcut's
    /// name. A hotkey of a shortcut taken off the favourites stays registered until the module stops
    /// (`ModuleHotkeys` cannot remove one), but does nothing.
    private func syncHotkeys() {
        guard let context, let keys else { return }
        for id in context.settings.value(keys.favorites) {
            let title = "Chạy \(name(of: id))"
            guard hotkeyTitles[id] != title else { continue }
            hotkeyTitles[id] = title
            context.hotkeys.register(ShortcutFavorites.hotkeyName(for: id), title: title) { [weak self] in
                guard let self, let context = self.context, let keys = self.keys,
                      context.settings.value(keys.favorites).contains(id) else { return }
                self.run(id)
            }
        }
    }

    /// Settings can change while the module runs; the hotkeys follow. The tracking fires once, so it is armed again.
    private func observeFavorites(_ context: ModuleContext) {
        guard let keys else { return }
        withObservationTracking {
            _ = context.settings.value(keys.favorites)
        } onChange: { [weak self] in
            // Called before the new value is stored; the hop lets the write finish.
            Task { @MainActor in
                guard let self, self.context === context else { return }
                self.syncHotkeys()
                self.observeFavorites(context)
            }
        }
    }

    // MARK: Running

    /// Starts a shortcut. Ignored while the same one is still running.
    func run(_ id: String) {
        guard let context, !state.running.contains(id) else { return }
        let name = name(of: id)
        state.running.insert(id)
        context.run { [weak self] in await self?.perform(id, name: name, context: context) }
    }

    private func perform(_ id: String, name: String, context: ModuleContext) async {
        defer { state.running.remove(id) }
        let output: String?
        do {
            output = try await cli.run(id: id)
        } catch is CancellationError {
            return
        } catch {
            guard self.context === context, !Task.isCancelled else { return }
            context.logger.error("Shortcut \(name, privacy: .public) failed: \(error, privacy: .public)")
            announce(.failed(message: Self.message(for: error)))
            return
        }
        guard self.context === context, !Task.isCancelled else { return }
        announce(.ran(name: name))
        if let output {
            context.presenter.showToast(AnyView(ShortcutOutputToast(text: output, copy: { [weak self] in self?.copy(output) })), duration: .seconds(8))
        }
    }

    /// The copy button of the output toast.
    func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func announce(_ result: ShortcutResult) {
        state.lastResult = result
        context?.activities.set(LiveActivity(
            id: Self.resultActivityID, expiresAfter: .seconds(3),
            leading: AnyView(ShortcutActivityIcon(systemImage: result.systemImage)),
            trailing: AnyView(ShortcutActivityText(text: result.text))
        ))
    }

    /// The name from the list, or the identifier while the list is not known.
    private func name(of id: String) -> String {
        state.shortcuts.first { $0.id == id }?.name ?? id
    }

    private static func message(for error: any Error) -> String {
        (error as? ShortcutsCLIError)?.message ?? "không chạy được"
    }
}
