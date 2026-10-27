import MyNotchCore
import SwiftUI

/// Plain rows: the Settings page provides the Form and the section. They work whether or not the module runs.
struct ScreenshotSettingsView: View {
    static let reconfirmationNote = "Từ macOS 15, hệ thống hỏi lại quyền Ghi màn hình khoảng mỗi tháng với app chụp màn hình. "
        + "Khi hộp thoại hiện ra, chọn “Cho phép” để tiếp tục chụp; MyNotch không thể tránh việc này."

    static let recordingNote = "Phím tắt quay và tạm dừng đặt trong trang Phím tắt. Ghi phím cần quyền Trợ năng; không có thì chỉ ghi chuột, "
        + "và MyNotch không bao giờ ghi phím nào, chỉ ghi lúc có phím được nhấn."

    static let exportedRecordingsNote = "Chỉ xoá bản quay gốc đã xuất ít nhất một lần, và chỉ khi không đang quay hay đang xuất. "
        + "File đã xuất ở ~/Movies/MyNotch luôn được giữ. Mặc định tắt: bản quay gốc không tự xoá."

    let settings: ModuleSettings
    let keys: ScreenshotSettingKeys

    /// By name, so the menu reads alphabetically.
    private let languages = OCRService.supportedLanguages.sorted { OCRLanguages.name(of: $0) < OCRLanguages.name(of: $1) }
    /// The microphones connected when the rows were built.
    @State private var microphones = MicrophoneDevice.available()

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
            Toggle("Tự động mở trình chỉnh sửa sau khi chụp", isOn: settings.binding(keys.autoOpenEditor))
            Picker("Nền phần mở rộng khi sửa ảnh", selection: settings.binding(keys.canvasFill)) {
                ForEach(CanvasFill.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            ocrLanguages
            Text(Self.reconfirmationNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            recording
        }
    }

    /// What a new recording starts with. The editor changes all of it per recording.
    @ViewBuilder private var recording: some View {
        Divider()
        Text("Quay màn hình").font(.headline)
        microphone
        Toggle("Ghi cả âm thanh của hệ thống", isOn: settings.binding(keys.recordSystemAudio))
        Toggle("Đếm ngược \(RecordingCoordinator.countdownSeconds) giây trước khi quay", isOn: settings.binding(keys.recordCountdown))
        Stepper(
            "Zoom khi bấm: \(settings.value(keys.zoomScale).formatted(.number.precision(.fractionLength(0...2))))×",
            value: settings.binding(keys.zoomScale), in: ScreenshotSettingKeys.zoomScaleRange, step: 0.25
        )
        Stepper(
            "Thu zoom về sau \(settings.value(keys.zoomHoldSeconds).formatted(.number.precision(.fractionLength(0...1)))) giây không thao tác",
            value: settings.binding(keys.zoomHoldSeconds), in: ScreenshotSettingKeys.zoomHoldRange, step: 0.5
        )
        Toggle("Hiện vòng tròn ở mỗi cú bấm", isOn: settings.binding(keys.clickEffect))
        Picker("Mức xuất mặc định", selection: settings.binding(keys.exportLevel)) {
            ForEach(ExportLevel.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        Text(Self.recordingNote)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        Toggle(
            "Xoá bản quay gốc đã xuất sau \(settings.value(keys.exportedRecordingDays)) ngày",
            isOn: settings.binding(keys.cleanExportedRecordings)
        )
        Stepper(
            "Số ngày: \(settings.value(keys.exportedRecordingDays))",
            value: settings.binding(keys.exportedRecordingDays), in: ScreenshotSettingKeys.exportedRecordingDaysRange
        )
        .disabled(!settings.value(keys.cleanExportedRecordings))
        Text(Self.exportedRecordingsNote)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The system's default, none, or one of the connected microphones. One that was chosen and is gone stays in the list, named as
    /// gone, so the picker never holds a value it has no row for; a recording then uses the system's default.
    private var microphone: some View {
        let stored = settings.value(keys.recordMicrophone)
        let isGone = ![MicrophoneChoice.systemDefault, MicrophoneChoice.off].contains(stored) && !microphones.contains { $0.id == stored }
        return Picker("Micro khi quay", selection: settings.binding(keys.recordMicrophone)) {
            Text("Mặc định của hệ thống").tag(MicrophoneChoice.systemDefault)
            Text("Không ghi tiếng").tag(MicrophoneChoice.off)
            ForEach(microphones) { Text($0.name).tag($0.id) }
            if isGone { Text("Micro đã chọn không còn kết nối").tag(stored) }
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
