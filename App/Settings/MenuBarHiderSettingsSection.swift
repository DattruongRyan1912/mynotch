import AppKit
import MyNotchCore
import SwiftUI

/// "Ẩn bớt icon trên menu bar": the settings of the separator ‹ that hides the icons on its left, and of ‹‹ for the zone that
/// stays hidden until asked for.
struct MenuBarHiderSettingsSection: View {
    let settings: SettingsStore

    private var isOn: Bool { settings.value(MenuBarHiderSettings.enabled) }
    private var iconShown: Bool { settings.value(AppSettings.showMenuBarIcon) }
    /// A display with a notch hides the icons that do not fit behind it, which is a different problem from the one here.
    private var hasNotchedDisplay: Bool { NSScreen.screens.contains { $0.safeAreaInsets.top > 0 } }

    var body: some View {
        Section("Icon trên menu bar") {
            Toggle("Ẩn bớt icon trên menu bar", isOn: settings.binding(MenuBarHiderSettings.enabled))
                .disabled(!iconShown && !isOn)
            VStack(alignment: .leading, spacing: 4) {
                Text("Cách dùng")
                    .font(.caption.weight(.semibold))
                Text("1. Giữ ⌘ rồi kéo icon của app khác sang bên trái dấu ‹ để ẩn chúng; để bên phải dấu ‹ thì chúng luôn hiện.")
                Text("2. Bấm icon MyNotch hoặc dấu ‹ để hiện hay ẩn các icon đã ẩn; bấm chuột phải vào icon MyNotch để mở menu.")
                Text("3. Nếu bấm mà chỉ nghe tiếng bíp, dấu ‹ đang nằm bên phải icon MyNotch: giữ ⌘ rồi kéo nó sang bên trái.")
                Text("Tắt Hidden Bar để tránh hai app cùng ẩn icon.")
            }
            .font(.caption).foregroundStyle(.secondary)
            if !iconShown {
                Text("Bật \"Hiện icon trên menu bar\" để dùng tính năng này: icon MyNotch là nút hiện và ẩn.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if isOn {
                Picker("Tự thu gọn", selection: settings.binding(MenuBarHiderSettings.autoCollapseSeconds)) {
                    ForEach(delays, id: \.self) { seconds in
                        Text(Self.label(seconds)).tag(seconds)
                    }
                }
                Text("Đếm từ lúc icon hiện ra, và tạm dừng khi con trỏ đang ở trên thanh menu.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Thu gọn ngay khi MyNotch khởi động", isOn: settings.binding(MenuBarHiderSettings.startCollapsed))
                Toggle("Thêm vùng luôn ẩn (dấu ‹‹)", isOn: settings.binding(MenuBarHiderSettings.alwaysHiddenSection))
                if settings.value(MenuBarHiderSettings.alwaysHiddenSection) {
                    Text("Icon bên trái dấu ‹‹ vẫn ẩn khi bạn bấm icon MyNotch. Để xem chúng, giữ ⌥ rồi bấm icon MyNotch (hoặc chọn \"Hiện cả icon luôn ẩn\" trong menu). Lúc đó mới kéo được icon sang bên trái dấu ‹‹; dấu ‹‹ phải nằm ngoài cùng bên trái, trước dấu ‹.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Phím tắt hiện/ẩn icon (chưa đặt sẵn): chọn ở mục Phím tắt bên dưới.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Hiện khi rê chuột lên thanh menu", isOn: settings.binding(MenuBarHiderSettings.revealOnHover))
                Text("Đưa con trỏ lên thanh menu để hiện các icon đã ẩn; rời đi một lát thì chúng ẩn lại.")
                    .font(.caption).foregroundStyle(.secondary)
                if hasNotchedDisplay {
                    Text("Máy có notch: khi menu bar đầy, macOS che các icon ở xa nhất sau notch. Kéo những icon bạn cần dùng sang bên phải dấu ‹; các icon bên trái sẽ ẩn khi thu gọn.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var delays: [Int] {
        let current = settings.value(MenuBarHiderSettings.autoCollapseSeconds)
        let standard = MenuBarHiderSettings.autoCollapseChoices
        return standard.contains(current) ? standard : (standard + [current]).sorted()
    }

    private static func label(_ seconds: Int) -> String {
        switch seconds {
        case 0: "Không tự thu gọn"
        case 1..<60: "Sau \(seconds) giây"
        default: seconds % 60 == 0 ? "Sau \(seconds / 60) phút" : "Sau \(seconds) giây"
        }
    }
}
