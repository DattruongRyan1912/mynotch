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
                Picker(selection: settings.binding(InterfaceSettings.displayMode)) {
                    Text("Tất cả màn hình").tag(DisplayMode.all)
                    Text("Màn hình chính").tag(DisplayMode.main)
                    Text("Màn hình đang dùng").tag(DisplayMode.cursor)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Màn hình hiển thị")
                        Text("Chuyển notch sang màn hình khác khi con trỏ dừng ở đó khoảng 0,3 giây")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Toggle("Ẩn khi ứng dụng đang toàn màn hình (fullscreen)", isOn: settings.binding(InterfaceSettings.hideInFullscreen))
            }

            Section {
                Picker("Tô đen thanh menu", selection: settings.binding(InterfaceSettings.blackMenuBar)) {
                    Text("Tắt").tag(BlackMenuBar.off)
                    Text("Chỉ màn hình có tai thỏ").tag(BlackMenuBar.notchedScreens)
                    Text("Mọi màn hình").tag(BlackMenuBar.allScreens)
                }
            } header: {
                Text("Thanh menu")
            } footer: {
                Text("Phủ một dải đen lên thanh menu để phần khuyết của máy liền với thanh. Dải đen tự ẩn khi app toàn màn hình hoặc thanh menu tự ẩn.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Kích thước notch ảo (màn hình không có tai thỏ)") {
                Picker("Kiểu dáng", selection: settings.binding(InterfaceSettings.virtualNotchStyle)) {
                    Text("Notch (sát mép trên)").tag(VirtualNotchStyle.notch)
                    Text("Viên thuốc (nổi)").tag(VirtualNotchStyle.pill)
                }

                slider("Chiều rộng", InterfaceSettings.virtualNotchWidth, 120...300, unit: "pt")

                if settings.value(InterfaceSettings.virtualNotchStyle) == .pill {
                    slider("Chiều cao viên thuốc", InterfaceSettings.pillHeight, NotchGeometry.pillHeightLimits, unit: "pt")
                } else {
                    Toggle("Cao bằng thanh menu bar", isOn: settings.binding(InterfaceSettings.virtualNotchMatchesMenuBar))
                    slider("Chiều cao", InterfaceSettings.virtualNotchHeight, 24...40, unit: "pt")
                        .disabled(settings.value(InterfaceSettings.virtualNotchMatchesMenuBar))
                }
            }

            Section("Khi mở rộng") {
                slider("Chiều rộng", InterfaceSettings.openWidth, NotchGeometry.openWidthLimits, unit: "pt")
                Stepper("Độ trễ khi mở: \(settings.value(InterfaceSettings.openDelayMs)) ms",
                        value: settings.binding(InterfaceSettings.openDelayMs), in: 0...1000, step: 50)
                Stepper("Độ trễ khi đóng: \(settings.value(InterfaceSettings.closeDelayMs)) ms",
                        value: settings.binding(InterfaceSettings.closeDelayMs), in: 0...1000, step: 50)
            }

            Section("Giao diện Liquid Glass") {
                Picker(selection: settings.binding(InterfaceSettings.look)) {
                    Text("Cổ điển (đen nguyên bản)").tag(NotchLook.classic)
                    Text("Liquid Glass (kính mờ)").tag(NotchLook.liquidGlass)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chất liệu notch")
                        Text("Liquid Glass sử dụng kính trong suốt đặc trưng của macOS")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Picker(selection: settings.binding(InterfaceSettings.glassClarity)) {
                    Text("Cân bằng").tag(NotchGlassClarity.balanced)
                    Text("Trong vắt").tag(NotchGlassClarity.clear)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Độ trong suốt")
                        Text("Trong vắt giống Control Center")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(!isLiquidGlass)

                Picker(selection: settings.binding(InterfaceSettings.glassShape)) {
                    Text("Một khối liền").tag(NotchGlassShape.slab)
                    Text("Các ô rời").tag(NotchGlassShape.tiles)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hình dạng khi mở")
                        Text("Ô rời: thanh thẻ và nội dung là hai mảnh kính riêng")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(!isLiquidGlass)

                Toggle(isOn: settings.binding(InterfaceSettings.glassTint)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nhuộm màu theo màu nhấn")
                        Text("Phủ một lớp nhẹ màu nhấn lên kính Liquid Glass")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(!isLiquidGlass)
            }

            Section("Màu sắc & Kính mờ") {
                LabeledContent {
                    AccentSwatches(settings: settings)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Màu nhấn")
                        Text("Màu của thẻ đang chọn, thanh tiến trình và công tắc")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: settings.binding(InterfaceSettings.glass)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kính mờ khi notch mở rộng (Cổ điển)")
                        Text("Làm mờ nhẹ phía sau nội dung khi notch mở")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(isLiquidGlass)
            }

            Section("Cử chỉ vuốt & Phản hồi") {
                Toggle(isOn: settings.binding(InterfaceSettings.swipeBetweenTabs)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vuốt hai ngón để chuyển thẻ")
                        Text("Vuốt ngang trên thanh thẻ hoặc vùng trống của notch")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: settings.binding(InterfaceSettings.swipeToOpen)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vuốt xuống để mở, vuốt lên để đóng")
                        Text("Đặt hai ngón tay lên vùng notch rồi vuốt dọc")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if settings.value(InterfaceSettings.swipeToOpen) {
                    Picker("Độ nhạy cử chỉ vuốt", selection: settings.binding(InterfaceSettings.swipeSensitivity)) {
                        Text("Thấp").tag(SwipeSensitivity.low)
                        Text("Vừa").tag(SwipeSensitivity.medium)
                        Text("Cao").tag(SwipeSensitivity.high)
                    }
                }

                Toggle(isOn: settings.binding(InterfaceSettings.haptics)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rung nhẹ khi vuốt (Haptic Feedback)")
                        Text("Phản hồi rung cơ học trên trackpad Force Touch")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
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
