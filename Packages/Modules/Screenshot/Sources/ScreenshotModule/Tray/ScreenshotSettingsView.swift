import MyNotchCore
import SwiftUI

/// Plain rows: the Settings page provides the Form and the section. They work whether or not the module runs.
struct ScreenshotSettingsView: View {
    static let reconfirmationNote = "Từ macOS 15, hệ thống hỏi lại quyền Ghi màn hình khoảng mỗi tháng với app chụp màn hình. "
        + "Khi hộp thoại hiện ra, chọn “Cho phép” để tiếp tục chụp; MyNotch không thể tránh việc này."

    let settings: ModuleSettings
    let keys: ScreenshotSettingKeys

    /// By name, so the menu reads alphabetically.
    private let languages = OCRService.supportedLanguages.sorted { OCRLanguages.name(of: $0) < OCRLanguages.name(of: $1) }

    var body: some View {
        Group {
            Toggle("Chép ảnh vào clipboard sau khi chụp", isOn: settings.binding(keys.copyToClipboard))
            Toggle("Chép ảnh vào clipboard khi sửa xong", isOn: settings.binding(keys.copyWhenDone))
            Stepper(
                "Giữ \(settings.value(keys.keepCount)) ảnh gần nhất",
                value: settings.binding(keys.keepCount), in: ScreenshotSettingKeys.keepCountRange, step: 5
            )
            Picker("Nơi lưu khi chọn “Lưu vào”", selection: settings.binding(keys.saveLocation)) {
                ForEach(SaveLocation.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle("Chụp cửa sổ kèm bóng đổ", isOn: settings.binding(keys.windowShadow))
            Toggle("Hiện ảnh vừa chụp kèm nút Sửa", isOn: settings.binding(keys.showCaptureChip))
            Picker("Nền phần mở rộng khi sửa ảnh", selection: settings.binding(keys.canvasFill)) {
                ForEach(CanvasFill.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            ocrLanguages
            Text(Self.reconfirmationNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A menu of checkmarks, one per language Vision can read; several can be on.
    private var ocrLanguages: some View {
        let selected = settings.value(keys.ocrLanguages)
        return LabeledContent("Ngôn ngữ nhận chữ") {
            Menu(OCRLanguages.summary(of: selected, supported: languages)) {
                ForEach(languages, id: \.maximalIdentifier) { language in
                    Toggle(OCRLanguages.name(of: language), isOn: Binding(
                        get: { OCRLanguages.isSelected(language, in: settings.value(keys.ocrLanguages), supported: languages) },
                        set: { _ in
                            settings.set(OCRLanguages.toggling(language, in: settings.value(keys.ocrLanguages), supported: languages), for: keys.ocrLanguages)
                        }
                    ))
                }
            }
            .fixedSize()
        }
    }
}
