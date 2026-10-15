import MyNotchCore
import NotchUI
import SwiftUI

struct InterfaceSettingsPage: View {
    let settings: SettingsStore

    var body: some View {
        Form {
            Section("Hiển thị") {
                Picker("Màn hình", selection: settings.binding(InterfaceSettings.displayMode)) {
                    Text("Tất cả màn hình").tag(DisplayMode.all)
                    Text("Màn hình chính").tag(DisplayMode.main)
                    Text("Màn hình đang dùng").tag(DisplayMode.cursor)
                }
                Text("Màn hình đang dùng: notch chuyển sang màn hình khác khi con trỏ ở lại đó khoảng 0,3 giây.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Ẩn khi app đang fullscreen", isOn: settings.binding(InterfaceSettings.hideInFullscreen))
            }
            Section("Kích thước notch ảo (màn hình không có notch)") {
                slider("Chiều rộng", InterfaceSettings.virtualNotchWidth, 120...300, unit: "pt")
                Toggle("Cao bằng menu bar", isOn: settings.binding(InterfaceSettings.virtualNotchMatchesMenuBar))
                slider("Chiều cao", InterfaceSettings.virtualNotchHeight, 24...40, unit: "pt")
                    .disabled(settings.value(InterfaceSettings.virtualNotchMatchesMenuBar))
            }
            Section("Khi mở rộng") {
                slider("Chiều rộng", InterfaceSettings.openWidth, NotchGeometry.openWidthLimits, unit: "pt")
                Stepper("Trễ khi mở: \(settings.value(InterfaceSettings.openDelayMs)) ms",
                        value: settings.binding(InterfaceSettings.openDelayMs), in: 0...1000, step: 50)
                Stepper("Trễ khi đóng: \(settings.value(InterfaceSettings.closeDelayMs)) ms",
                        value: settings.binding(InterfaceSettings.closeDelayMs), in: 0...1000, step: 50)
                Toggle("Vuốt hai ngón để chuyển trang", isOn: settings.binding(InterfaceSettings.swipeBetweenTabs))
                Text("Vuốt ngang trên thanh trang hoặc vùng trống của notch. Nội dung tự cuộn ngang, như băng clipboard, giữ cử chỉ của nó.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Interface")
    }

    private func slider(_ title: String, _ key: SettingKey<Double>, _ range: ClosedRange<CGFloat>, unit: String) -> some View {
        LabeledContent("\(title): \(Int(settings.value(key))) \(unit)") {
            Slider(value: settings.binding(key), in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
        }
    }
}
