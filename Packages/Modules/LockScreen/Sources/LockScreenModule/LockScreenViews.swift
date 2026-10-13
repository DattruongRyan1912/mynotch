import MyNotchCore
import NotchUI
import SwiftUI

/// What the panel shows: the best view the user allows, on the notch's black. It reads the center itself, so a
/// contributor that changes while the screen is locked changes what is shown without rebuilding the panel.
struct LockScreenRootView: View {
    let lockScreen: LockScreenPublisher
    let isAllowed: (ModuleID) -> Bool

    var body: some View {
        if let entry = lockScreen.current(allowing: isAllowed) {
            entry.view
                .id(entry.module)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(NotchTokens.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Plain rows: the Settings page provides the Form and the section.
struct LockScreenSettingsView: View {
    static let warning = "Thử nghiệm — dùng API riêng của macOS"

    let settings: ModuleSettings
    let keys: LockScreenKeys

    var body: some View {
        Group {
            Label(Self.warning, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Toggle("Hiện bài đang phát", isOn: settings.binding(keys.showMedia))
            Toggle("Hiện hẹn giờ", isOn: settings.binding(keys.showTimer))
            Toggle("Hiện pin", isOn: settings.binding(keys.showBattery))
        }
    }
}
