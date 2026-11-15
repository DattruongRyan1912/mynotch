import MyNotchCore
import SwiftUI

/// Các khoá cài đặt cho phân hệ Thói quen.
public struct HabitSettingsKeys {
    /// Bật/tắt hiển thị số thói quen còn lại trong ngày trên Notch.
    public let showRemaining: SettingKey<Bool>

    public init(_ settings: ModuleSettings) {
        showRemaining = settings.key("showRemaining", default: false)
    }
}

/// Snapshot cấu hình đọc một lần từ ModuleSettings.
nonisolated public struct HabitSettings: Equatable, Sendable {
    public var showRemaining: Bool

    @MainActor
    public init(_ settings: ModuleSettings) {
        let keys = HabitSettingsKeys(settings)
        showRemaining = settings.value(keys.showRemaining)
    }
}

/// Giao diện cấu hình phân hệ trong Settings của app.
public struct HabitSettingsView: View {
    let settings: ModuleSettings
    let keys: HabitSettingsKeys

    public init(settings: ModuleSettings) {
        self.settings = settings
        self.keys = HabitSettingsKeys(settings)
    }

    public var body: some View {
        Toggle("Hiện số thói quen còn lại trên notch", isOn: settings.binding(keys.showRemaining))
    }
}
