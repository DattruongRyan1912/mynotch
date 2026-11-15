import MyNotchCore
import SwiftUI

/// Setting names and defaults in one place, shared by the running module and the Settings rows.
struct WindowLayoutKeys {
    /// Ids of the layouts that get a tile (`SnapLayout.rawValue`); stored as text so an id a later version drops is
    /// ignored instead of spoiling the whole list.
    let layouts: SettingKey<[String]>
    let gap: SettingKey<SnapGap>

    init(_ settings: ModuleSettings) {
        layouts = settings.key("layouts", default: SnapLayout.allCases.map(\.rawValue))
        gap = settings.key("gap", default: SnapGap.none)
    }

    func options(_ settings: ModuleSettings) -> SnapOptions {
        SnapOptions(storedLayouts: settings.value(layouts), gap: settings.value(gap))
    }
}

extension SnapOptions {
    /// The ids to store after `layout` is switched on or off, in the tiles' order. The last layout cannot be switched
    /// off: with no tile at all the module would do nothing and not say why.
    func storedLayouts(setting layout: SnapLayout, to isOn: Bool) -> [String] {
        var chosen = Set(layouts)
        if isOn {
            chosen.insert(layout)
        } else if chosen.count > 1 {
            chosen.remove(layout)
        }
        return SnapLayout.allCases.filter(chosen.contains).map(\.rawValue)
    }
}

/// Plain rows: the Settings page provides the Form and the section.
struct WindowLayoutSettingsView: View {
    let settings: ModuleSettings
    let keys: WindowLayoutKeys

    private var options: SnapOptions { keys.options(settings) }

    var body: some View {
        Group {
            Text("Kéo một cửa sổ lên notch rồi thả vào một ô để đặt nó vào vị trí đó. Nhấn Esc khi đang kéo để huỷ.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(SnapLayout.allCases) { layout in
                Toggle(layout.title, isOn: binding(for: layout))
                    // The last one on has to stay, so the row says so by being dimmed.
                    .disabled(options.layouts == [layout])
            }
            Picker("Khoảng cách giữa các cửa sổ", selection: settings.binding(keys.gap)) {
                ForEach(SnapGap.allCases, id: \.self) { gap in
                    Text(gap == .none ? "Không" : "\(gap.rawValue) pt").tag(gap)
                }
            }
        }
    }

    private func binding(for layout: SnapLayout) -> Binding<Bool> {
        Binding(
            get: { options.layouts.contains(layout) },
            set: { settings.set(options.storedLayouts(setting: layout, to: $0), for: keys.layouts) }
        )
    }
}
