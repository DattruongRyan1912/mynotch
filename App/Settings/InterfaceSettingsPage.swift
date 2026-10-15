import AppKit
import MyNotchCore
import NotchUI
import SwiftUI

struct InterfaceSettingsPage: View {
    let settings: SettingsStore

    private var isLiquidGlass: Bool { settings.value(InterfaceSettings.look) == .liquidGlass }

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
            }
            Section("Giao diện notch") {
                Picker("Kiểu", selection: settings.binding(InterfaceSettings.look)) {
                    Text("Cổ điển (đen)").tag(NotchLook.classic)
                    Text("Liquid Glass").tag(NotchLook.liquidGlass)
                }
                Text("Liquid Glass: notch thu gọn, notch mở rộng, bong bóng và thông báo là một khối kính trong suốt của macOS 26. Trên máy có phần khuyết, kính hiện quanh phần khuyết.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Nhuộm theo màu nhấn", isOn: settings.binding(InterfaceSettings.glassTint))
                    .disabled(!isLiquidGlass)
                Text("Phủ một lớp nhẹ màu nhấn lên kính. Chỉ dùng cho Liquid Glass.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Màu sắc") {
                LabeledContent("Màu nhấn") { AccentSwatches(settings: settings) }
                Text("Màu của trang đang chọn, thanh tiến trình và công tắc trong notch. Nền notch đen ở giao diện Cổ điển và là kính ở Liquid Glass.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Kính mờ khi notch mở rộng", isOn: settings.binding(InterfaceSettings.glass))
                    .disabled(isLiquidGlass)
                Text(isLiquidGlass
                    ? "Liquid Glass đang bật nên không dùng kính mờ. Lựa chọn này được giữ cho khi bạn quay lại Cổ điển."
                    : "Làm mờ nhẹ phía sau nội dung khi notch mở. Notch thu gọn vẫn đen để khớp với phần khuyết của máy.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Cử chỉ") {
                Toggle("Vuốt hai ngón để chuyển trang", isOn: settings.binding(InterfaceSettings.swipeBetweenTabs))
                Text("Vuốt ngang trên thanh trang hoặc vùng trống của notch. Nội dung tự cuộn ngang, như băng clipboard, giữ cử chỉ của nó.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Vuốt xuống để mở, vuốt lên để đóng", isOn: settings.binding(InterfaceSettings.swipeToOpen))
                Picker("Độ nhạy", selection: settings.binding(InterfaceSettings.swipeSensitivity)) {
                    Text("Thấp").tag(SwipeSensitivity.low)
                    Text("Vừa").tag(SwipeSensitivity.medium)
                    Text("Cao").tag(SwipeSensitivity.high)
                }
                .disabled(!settings.value(InterfaceSettings.swipeToOpen))
                Text("Đặt hai ngón lên notch rồi vuốt dọc. Chỉ tính khi con trỏ đang ở trên notch và cử chỉ bắt đầu ở đó.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Rung nhẹ khi vuốt", isOn: settings.binding(InterfaceSettings.haptics))
                Text("Mở, đóng notch hoặc đổi trang bằng cử chỉ có phản hồi rung nhẹ. Chỉ có trên trackpad Force Touch.")
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

/// The accent as swatches: macOS's own, the eight colours of its picker, and a colour picker for any other.
private struct AccentSwatches: View {
    let settings: SettingsStore
    /// Counts the changes of macOS's own accent, so the "Hệ thống" swatch is drawn again with the new colour.
    @State private var systemColorChanges = 0

    private var current: NotchAccent { settings.value(InterfaceSettings.accent) }

    var body: some View {
        let _ = systemColorChanges
        HStack(spacing: 8) {
            choice(.system, label: "Hệ thống") {
                HStack(spacing: 5) {
                    Circle().fill(NotchAccent.system.color).frame(width: 12, height: 12)
                    Text("Hệ thống").font(.callout)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
            }
            ForEach(NotchAccent.Palette.allCases, id: \.self) { palette in
                choice(.palette(palette), label: palette.label) {
                    Circle().fill(NotchAccent.palette(palette).color).frame(width: 18, height: 18).padding(2)
                }
            }
            ColorPicker("Màu tùy chọn", selection: customColor, supportsOpacity: false)
                .labelsHidden()
                .overlay { ring(isCustom) }
                .help("Màu tùy chọn")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSColor.systemColorsDidChangeNotification)) { _ in systemColorChanges += 1 }
    }

    private var isCustom: Bool {
        if case .custom = current { true } else { false }
    }

    /// The custom colour while one is chosen, else the colour in use, so the picker opens where the eye is.
    private var customColor: Binding<Color> {
        Binding(
            get: {
                if case .custom(let rgb) = current { rgb.color } else { current.color }
            },
            set: { settings.set(NotchAccent(color: $0), for: InterfaceSettings.accent) }
        )
    }

    private func choice<Content: View>(_ accent: NotchAccent, label: String, @ViewBuilder content: () -> Content) -> some View {
        Button { settings.set(accent, for: InterfaceSettings.accent) } label: {
            content().overlay { ring(current == accent) }
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(current == accent ? .isSelected : [])
    }

    private func ring(_ selected: Bool) -> some View {
        Capsule().strokeBorder(Color.primary.opacity(selected ? 0.8 : 0), lineWidth: 2).allowsHitTesting(false)
    }
}

private extension NotchAccent.Palette {
    var label: String {
        switch self {
        case .blue: "Xanh dương"
        case .purple: "Tím"
        case .pink: "Hồng"
        case .red: "Đỏ"
        case .orange: "Cam"
        case .yellow: "Vàng"
        case .green: "Xanh lá"
        case .graphite: "Xám"
        }
    }
}
