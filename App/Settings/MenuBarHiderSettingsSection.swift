import AppKit
import MyNotchCore
import SwiftUI

/// "Ẩn bớt icon trên menu bar": the settings of the separator ‹ that hides the icons on its left.
struct MenuBarHiderSettingsSection: View {
    let settings: SettingsStore

    private static let standardDelays = [0, 3, 5, 10, 15, 30, 60, 120]

    private var isOn: Bool { settings.value(MenuBarHiderSettings.enabled) }
    private var iconShown: Bool { settings.value(AppSettings.showMenuBarIcon) }
    /// A display with a notch hides the icons that do not fit behind it, which is a different problem from the one here.
    private var hasNotchedDisplay: Bool { NSScreen.screens.contains { $0.safeAreaInsets.top > 0 } }

    var body: some View {
        Section("Icon trên menu bar") {
            Toggle("Ẩn bớt icon trên menu bar", isOn: settings.binding(MenuBarHiderSettings.enabled))
                .disabled(!iconShown && !isOn)
            Text("Thêm dấu ‹ cạnh icon MyNotch. Giữ ⌘ rồi kéo icon của app khác sang bên trái dấu ‹ để ẩn chúng. Bấm icon MyNotch để hiện hoặc ẩn; bấm chuột phải để mở menu.")
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
        return Self.standardDelays.contains(current) ? Self.standardDelays : (Self.standardDelays + [current]).sorted()
    }

    private static func label(_ seconds: Int) -> String {
        switch seconds {
        case 0: "Không tự thu gọn"
        case 1..<60: "Sau \(seconds) giây"
        default: seconds % 60 == 0 ? "Sau \(seconds / 60) phút" : "Sau \(seconds) giây"
        }
    }
}
