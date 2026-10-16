import AppKit
import ApplicationServices
import MyNotchCore
import SwiftUI

/// "Ẩn bớt icon trên menu bar": the settings of the separator ‹ that hides the icons on its left, of ‹‹ for the zone that
/// stays hidden until asked for, and of the bar under the menu bar that shows the icons the notch hides.
struct MenuBarHiderSettingsSection: View {
    let settings: SettingsStore

    private var isOn: Bool { settings.value(MenuBarHiderSettings.enabled) }
    private var iconShown: Bool { settings.value(AppSettings.showMenuBarIcon) }
    private var barOn: Bool { settings.value(MenuBarHiderSettings.itemsBar) }
    /// The bar lists the icons through Accessibility. Reading the status never prompts.
    private var accessibilityGranted: Bool { AXIsProcessTrusted() }
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
                Text(barOn
                    ? "2. Bấm icon MyNotch hoặc dấu ‹ để mở thanh icon ẩn dưới menu bar; giữ ⌥ khi bấm để hiện icon ngay trên menu bar. Bấm chuột phải vào icon MyNotch để mở menu."
                    : "2. Bấm icon MyNotch hoặc dấu ‹ để hiện hay ẩn các icon đã ẩn; bấm chuột phải vào icon MyNotch để mở menu.")
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
                Text("Đếm từ lúc icon hoặc thanh icon ẩn hiện ra, và tạm dừng khi con trỏ đang ở trên thanh menu hoặc thanh icon ẩn.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Hiện icon ẩn trong thanh riêng", isOn: settings.binding(MenuBarHiderSettings.itemsBar))
                Text("Thanh nhỏ dưới menu bar có các icon đang ẩn hoặc bị notch che; bấm vào icon để mở menu của nó (chuột phải: mở menu thay vì bấm thường). Thanh đóng khi bấm ra ngoài, nhấn Esc hoặc hết thời gian tự thu gọn. Icon của macOS không nằm trong thanh.")
                    .font(.caption).foregroundStyle(.secondary)
                if barOn, !accessibilityGranted {
                    Text("Cần quyền Trợ năng (mục Quyền) để liệt kê icon; chưa có thì bấm icon MyNotch vẫn hiện icon ngay trên menu bar. Có thêm quyền Ghi màn hình thì thanh vẽ icon đúng như trên menu bar, không thì dùng icon của app.")
                        .font(.caption).foregroundStyle(.orange)
                }
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
                    Text(barOn
                        ? "Máy có notch: khi menu bar đầy, macOS che các icon ở xa nhất sau notch; các icon đó hiện trong thanh icon ẩn. Kéo những icon bạn cần dùng sang bên phải dấu ‹ để chúng luôn nằm trên menu bar."
                        : "Máy có notch: khi menu bar đầy, macOS che các icon ở xa nhất sau notch. Kéo những icon bạn cần dùng sang bên phải dấu ‹; các icon bên trái sẽ ẩn khi thu gọn.")
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
