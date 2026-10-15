import MyNotchCore
import NotchUI
import SwiftUI

/// What the panel shows: the best view the user allows, on the notch's black. It reads the center itself, so a
/// contributor that changes while the screen is locked changes what is shown without rebuilding the panel.
struct LockScreenRootView: View {
    /// The card is this tall at least; a view with controls and a progress bar makes it taller, up to the panel's height.
    static let minimumHeight: CGFloat = 56
    static let verticalPadding: CGFloat = 8

    let lockScreen: LockScreenPublisher
    let isAllowed: (ModuleID) -> Bool
    /// The user lets a view with buttons draw them ("Điều khiển nhạc trên màn hình khoá"); read here, so a change reaches the view.
    let controlsEnabled: () -> Bool

    var body: some View {
        if let entry = lockScreen.current(allowing: isAllowed) {
            entry.view
                .environment(\.lockScreenControlsEnabled, controlsEnabled())
                .id(entry.module)
                .padding(.horizontal, 16)
                .padding(.vertical, Self.verticalPadding)
                .frame(maxWidth: .infinity, minHeight: Self.minimumHeight)
                .background(NotchTokens.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Plain rows: the Settings page provides the Form and the section.
struct LockScreenSettingsView: View {
    static let warning = "Thử nghiệm — dùng API riêng của macOS"
    static let mediaExplanation = "Hiện bìa, tên bài, nghệ sĩ và thanh tiến trình của nhạc đang phát."
    static let controlsTitle = "Điều khiển nhạc trên màn hình khoá"
    /// Says what the buttons let a stranger at the keyboard do, because they are the one thing here that can be clicked.
    static let controlsExplanation = "Thêm nút phát/dừng, bài trước và bài sau. Ai đứng trước máy cũng bấm được các nút này. Tắt đi thì chỉ xem được bài đang phát."

    let settings: ModuleSettings
    let keys: LockScreenKeys

    var body: some View {
        Group {
            Label(Self.warning, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Toggle(isOn: settings.binding(keys.showMedia)) {
                Text("Hiện bài đang phát")
                Text(Self.mediaExplanation)
            }
            Toggle(isOn: settings.binding(keys.showMediaControls)) {
                Text(Self.controlsTitle)
                Text(Self.controlsExplanation)
            }
            .disabled(!settings.value(keys.showMedia))
            Toggle("Hiện hẹn giờ", isOn: settings.binding(keys.showTimer))
            Toggle("Hiện pin", isOn: settings.binding(keys.showBattery))
        }
    }
}
