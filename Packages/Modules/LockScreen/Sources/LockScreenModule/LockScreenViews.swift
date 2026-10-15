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
    /// Whether the lock screen can be seen. The view's timelines and sweeps read it as `notchIsOnScreen` and stand still while it
    /// is false (the display sleeps), the way the notch's do.
    let presence: LockScreenPresence
    /// The user lets a view with buttons draw them ("Điều khiển nhạc trên màn hình khoá"); read here, so a change reaches the view.
    let controlsEnabled: () -> Bool
    /// The user lets a view show lyrics ("Hiện lời bài hát trên màn hình khoá"); read here too.
    let lyricsEnabled: () -> Bool

    var body: some View {
        if let entry = lockScreen.current(allowing: isAllowed) {
            entry.view
                .environment(\.lockScreenControlsEnabled, controlsEnabled())
                .environment(\.lockScreenLyricsEnabled, lyricsEnabled())
                .environment(\.notchIsOnScreen, presence.isOnScreen)
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
    static let lyricsTitle = "Hiện lời bài hát trên màn hình khoá"
    /// Lyrics are public text; this says nothing else is added, because the lock screen is read over the user's shoulder.
    static let lyricsExplanation = "Hiện dòng đang hát và dòng kế tiếp dưới tên bài, tô theo từng chữ khi lời có thời gian từng chữ và “Tô theo từng chữ” của Media đang bật. Chỉ là lời bài hát, nội dung công khai; không thêm gì khác lên màn hình khoá."

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
            Toggle(isOn: settings.binding(keys.showLyrics)) {
                Text(Self.lyricsTitle)
                Text(Self.lyricsExplanation)
            }
            .disabled(!settings.value(keys.showMedia))
            Toggle("Hiện hẹn giờ", isOn: settings.binding(keys.showTimer))
            Toggle("Hiện pin", isOn: settings.binding(keys.showBattery))
        }
    }
}
