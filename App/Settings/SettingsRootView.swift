import MyNotchCore
import Observation
import SwiftUI

enum SettingsPage: Hashable {
    case permissions, general, interface, storage, tabs, module(ModuleID), about
}

/// The page the Settings window shows. Held outside the view so the app can open a particular page (the nudge opens
/// "Quyền") whether or not the window exists yet.
@Observable
final class SettingsNavigation {
    var selection: SettingsPage? = .general
    /// Whether the window can be seen, set by `SettingsWindowController` for whatever only matters while it is.
    var isWindowVisible = false
}

struct SettingsRootView: View {
    let settings: SettingsStore
    let registry: ModuleRegistry
    let permissions: any PermissionCenter
    let overview: PermissionOverview
    let hotkeys: HotkeyRegistry
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.selection) {
                Label("Quyền", systemImage: "lock.shield").tag(SettingsPage.permissions)
                    .badge(overview.missingRequiredCount)
                Label("Chung", systemImage: "gearshape").tag(SettingsPage.general)
                Label("Giao diện", systemImage: "rectangle.topthird.inset.filled").tag(SettingsPage.interface)
                Label("Dung lượng", systemImage: "internaldrive").tag(SettingsPage.storage)
                Label("Trang trên notch", systemImage: "rectangle.3.group").tag(SettingsPage.tabs)
                Section("Mô-đun") {
                    ForEach(registry.modules, id: \.descriptor.id) { module in
                        Label(module.descriptor.displayName, systemImage: module.descriptor.systemImage)
                            .tag(SettingsPage.module(module.descriptor.id))
                    }
                }
                Section {
                    Label("Giới thiệu", systemImage: "info.circle").tag(SettingsPage.about)
                }
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            switch navigation.selection ?? .general {
            case .permissions: PermissionsPage(overview: overview)
            case .general: GeneralSettingsPage(settings: settings, hotkeys: hotkeys)
            case .interface: InterfaceSettingsPage(settings: settings)
            case .storage: StoragePage(settings: settings, registry: registry, openModule: { navigation.selection = .module($0) })
            case .tabs: TabOrderSettingsPage(settings: settings, registry: registry)
            case .module(let id): ModuleSettingsPage(id: id, registry: registry, permissions: permissions).id(id)
            case .about: AboutPage()
            }
        }
    }
}
