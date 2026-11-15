/// System permissions a module can require.
nonisolated public enum Permission: Hashable, Sendable {
    case accessibility
    case screenRecording
    case calendars
    case reminders
    case bluetooth
    case automation(bundleID: String)
    case microphone
    /// A Core Audio tap of what the system plays (Media's real spectrum, the equalizer). macOS reports no status for it.
    case systemAudio
    /// Listing the folder. macOS asks the first time and reports no status afterwards.
    case downloadsFolder
    case desktopFolder
    /// "Paste from Other Apps": reading what another app copied without the system asking each time.
    case pasteboard

    /// What the user sees, in Vietnamese. System Settings names live in `instruction`.
    public var displayName: String {
        switch self {
        case .accessibility: "Trợ năng"
        case .screenRecording: "Ghi màn hình"
        case .calendars: "Lịch"
        case .reminders: "Lời nhắc"
        case .bluetooth: "Bluetooth"
        case .automation(let bundleID): "Điều khiển \(bundleID)"
        case .microphone: "Micrô"
        case .systemAudio: "Ghi âm thanh hệ thống"
        case .downloadsFolder: "Thư mục Downloads"
        case .desktopFolder: "Thư mục Desktop"
        case .pasteboard: "Dán từ app khác"
        }
    }

    public var systemImage: String {
        switch self {
        case .accessibility: "accessibility"
        case .screenRecording: "record.circle"
        case .calendars: "calendar"
        case .reminders: "checklist"
        case .bluetooth: "dot.radiowaves.right"
        case .automation: "gearshape.2"
        case .microphone: "mic"
        case .systemAudio: "waveform"
        case .downloadsFolder: "arrow.down.circle"
        case .desktopFolder: "desktopcomputer"
        case .pasteboard: "doc.on.clipboard"
        }
    }

    /// What the permission lets MyNotch do, in one line. The Permissions page falls back to it for a module that
    /// gives no reason of its own.
    public var summary: String {
        switch self {
        case .accessibility: "Cho MyNotch dán nội dung và đọc văn bản bạn đang chọn."
        case .screenRecording: "Cho MyNotch chụp màn hình."
        case .calendars: "Cho MyNotch đọc sự kiện trong Lịch."
        case .reminders: "Cho MyNotch đọc lời nhắc."
        case .bluetooth: "Cho MyNotch biết thiết bị Bluetooth nào đang kết nối."
        case .automation(let bundleID): "Cho MyNotch điều khiển ứng dụng \(bundleID)."
        case .microphone: "Cho MyNotch dùng micro."
        case .systemAudio: "Cho MyNotch nghe âm thanh đang phát để vẽ phổ nhạc và chỉnh âm (EQ)."
        case .downloadsFolder: "Cho MyNotch xem và lưu file trong thư mục Downloads."
        case .desktopFolder: "Cho MyNotch lưu file vào thư mục Desktop."
        case .pasteboard: "Cho MyNotch đọc nội dung bạn chép từ app khác mà không hỏi lại mỗi lần."
        }
    }

    /// The step the user does in System Settings, naming the list in Vietnamese and as English macOS shows it.
    public var instruction: String { "Bật MyNotch trong danh sách \(paneName) rồi quay lại." + (hint.map { " " + $0 } ?? "") }

    /// What else to do there, when switching MyNotch on is not the whole step.
    private var hint: String? {
        switch self {
        case .systemAudio: "Chưa thấy MyNotch trong danh sách? Bật phổ âm thanh thật trong Media hoặc bật EQ trong tab Âm thanh để macOS hỏi trước."
        case .pasteboard: "Chọn “Luôn cho phép” (Always Allow) cho MyNotch."
        default: nil
        }
    }

    private var paneName: String {
        switch self {
        case .accessibility: "Trợ năng (Accessibility)"
        case .screenRecording: "Ghi màn hình và âm thanh hệ thống (Screen & System Audio Recording)"
        case .calendars: "Lịch (Calendars)"
        case .reminders: "Lời nhắc (Reminders)"
        case .bluetooth: "Bluetooth"
        case .automation: "Tự động hóa (Automation)"
        case .microphone: "Micrô (Microphone)"
        case .downloadsFolder, .desktopFolder: "Tệp và thư mục (Files & Folders)"
        case .systemAudio: "Chỉ ghi âm thanh hệ thống (System Audio Recording Only)"
        case .pasteboard: "Dán từ app khác (Paste from Other Apps)"
        }
    }

    /// The status can't tell "never asked" from "denied", and only `request` lists the app in System Settings,
    /// so granting always requests first and then opens System Settings if that was not enough.
    public var isSettingsOnly: Bool {
        switch self {
        case .accessibility, .screenRecording: true
        default: false
        }
    }

    /// No API shows a prompt for it, so granting is switching it on in System Settings; `request` only reports the status.
    public var isPaneOnly: Bool {
        switch self {
        case .systemAudio, .pasteboard: true
        default: false
        }
    }

    /// macOS leaves it at "not determined" until the user opens its pane (the system's own default behaviour), so that state
    /// is where most people stay and not a sign that something is waiting to be answered.
    public var restsAsNotDetermined: Bool { self == .pasteboard }

    /// What the grant button does now. Promptable permissions are requested until the user has answered once
    /// (macOS shows the prompt a single time); after a refusal only System Settings can change the answer.
    public func grantAction(for status: PermissionStatus) -> PermissionGrantAction {
        if isPaneOnly { return .openSettings }
        if isSettingsOnly { return .request }
        return status == .denied ? .openSettings : .request
    }

    /// Whether the page spells out the step in System Settings: the permission is not granted and the pane is where it
    /// gets granted (alone, or after the request), or macOS cannot say (`unknown`), so the user may need the pane too.
    public func showsInstruction(for status: PermissionStatus) -> Bool {
        status != .granted && (status == .unknown || isSettingsOnly || grantAction(for: status) == .openSettings)
    }

    /// Deep link into the matching System Settings privacy pane.
    public var settingsURL: String {
        let base = "x-apple.systempreferences:com.apple.preference.security?"
        return switch self {
        case .accessibility: base + "Privacy_Accessibility"
        case .screenRecording: base + "Privacy_ScreenCapture"
        case .calendars: base + "Privacy_Calendars"
        case .reminders: base + "Privacy_Reminders"
        case .bluetooth: base + "Privacy_Bluetooth"
        case .automation: base + "Privacy_Automation"
        case .microphone: base + "Privacy_Microphone"
        case .systemAudio: base + "Privacy_AudioCapture"
        case .downloadsFolder, .desktopFolder: base + "Privacy_FilesAndFolders"
        case .pasteboard: base + "Privacy_Pasteboard"
        }
    }
}

nonisolated public enum PermissionStatus: Sendable, Equatable {
    case granted
    case denied
    case notDetermined
    /// macOS gives no answer without prompting (system audio, folders); only using the feature settles it.
    case unknown

    /// Worth asking the user about. `unknown` is not: it would nag about something nobody can check.
    public var isMissing: Bool { self == .denied || self == .notDetermined }
}

nonisolated public enum PermissionGrantAction: Sendable, Equatable {
    case request
    case openSettings
}

/// One permission as the Permissions page shows it, with every module that uses it.
nonisolated public struct PermissionRequirement: Identifiable, Equatable, Sendable {
    nonisolated public struct Use: Equatable, Sendable {
        public let module: ModuleID
        public let moduleName: String
        public let isRequired: Bool
        /// One line on why this module needs it.
        public let reason: String
    }

    public let permission: Permission
    public let uses: [Use]

    public var id: Permission { permission }
    /// Some module cannot run without it.
    public var isRequired: Bool { uses.contains { $0.isRequired } }

    /// What the given modules need together: one entry per permission, required ones first, each group in the order
    /// the modules (then their declarations) mention them. A module that lists a permission as both counts it as required.
    public static func aggregate(_ descriptors: [ModuleDescriptor]) -> [PermissionRequirement] {
        var order: [Permission] = []
        var uses: [Permission: [Use]] = [:]
        for descriptor in descriptors {
            let declared = descriptor.permissions.map { ($0, true) } + descriptor.optionalPermissions.map { ($0, false) }
            var seen: Set<Permission> = []
            for (permission, isRequired) in declared where seen.insert(permission).inserted {
                if uses[permission] == nil { order.append(permission) }
                uses[permission, default: []].append(Use(
                    module: descriptor.id, moduleName: descriptor.displayName, isRequired: isRequired,
                    reason: descriptor.permissionReasons[permission] ?? permission.summary
                ))
            }
        }
        let all = order.map { PermissionRequirement(permission: $0, uses: uses[$0] ?? []) }
        return all.filter(\.isRequired) + all.filter { !$0.isRequired }
    }
}
