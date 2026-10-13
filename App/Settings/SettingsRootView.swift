import MyNotchCore
import SwiftUI

enum SettingsPage: Hashable {
    case general, interface, module(ModuleID), about
}

struct SettingsRootView: View {
    let settings: SettingsStore
    let registry: ModuleRegistry
    let permissions: any PermissionCenter
    let hotkeys: HotkeyRegistry
    @State private var selection: SettingsPage? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape").tag(SettingsPage.general)
                Label("Interface", systemImage: "rectangle.topthird.inset.filled").tag(SettingsPage.interface)
                Section("Modules") {
                    ForEach(registry.modules, id: \.descriptor.id) { module in
                        Label(module.descriptor.displayName, systemImage: module.descriptor.systemImage)
                            .tag(SettingsPage.module(module.descriptor.id))
                    }
                }
                Section {
                    Label("About", systemImage: "info.circle").tag(SettingsPage.about)
                }
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            switch selection ?? .general {
            case .general: GeneralSettingsPage(settings: settings, hotkeys: hotkeys)
            case .interface: InterfaceSettingsPage(settings: settings)
            case .module(let id): ModuleSettingsPage(id: id, registry: registry, permissions: permissions)
            case .about: AboutPage()
            }
        }
    }
}
