import AppKit
import ApplicationServices
import MyNotchCore
import SwiftUI

/// "Ẩn bớt icon trên menu bar": the settings of hiding the icons left of the MyNotch icon, and of the bar under the menu bar
/// that shows them.
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
        Section {
            Toggle(isOn: settings.binding(MenuBarHiderSettings.enabled)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ẩn bớt biểu tượng trên menu bar")
                    Text("Ẩn các biểu tượng nằm bên trái icon MyNotch để thanh menu luôn gọn gàng")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(!iconShown && !isOn)

            if !iconShown {
                Text("Bật \"Hiện biểu tượng trên menu bar\" ở trên để sử dụng tính năng này.")
                    .font(.caption).foregroundStyle(.orange)
            }

            if isOn {
                Picker("Thời gian tự thu gọn", selection: settings.binding(MenuBarHiderSettings.autoCollapseSeconds)) {
                    ForEach(delays, id: \.self) { seconds in
                        Text(Self.label(seconds)).tag(seconds)
                    }
                }

                Toggle(isOn: settings.binding(MenuBarHiderSettings.itemsBar)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hiện biểu tượng ẩn trong thanh riêng")
                        Text("Thanh nhỏ bên dưới menu bar chứa các icon đang ẩn hoặc bị notch che")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if barOn, !accessibilityGranted {
                    Text("Cần cấp quyền Trợ năng (mục Quyền) để ứng dụng có thể phát hiện và hiển thị các biểu tượng.")
                        .font(.caption).foregroundStyle(.orange)
                }

                Toggle(isOn: settings.binding(MenuBarHiderSettings.startCollapsed)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Thu gọn ngay khi MyNotch khởi động")
                        Text("Tự động ẩn các icon menu bar ngay khi mở app")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: settings.binding(MenuBarHiderSettings.revealOnHover)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hiện khi rê chuột lên thanh menu")
                        Text("Di chuyển con trỏ lên vùng menu bar để hiện các biểu tượng ẩn")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Biểu tượng trên Menu Bar")
        } footer: {
            if isOn {
                Text("Mẹo: Giữ phím ⌘ rồi kéo icon của app khác sang bên phải icon MyNotch để luôn hiện. Nhấp vào icon MyNotch để chuyển đổi hiện/ẩn.")
                    .font(.caption).foregroundStyle(.secondary)
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
