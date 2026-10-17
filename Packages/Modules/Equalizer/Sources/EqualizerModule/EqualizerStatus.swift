import Observation

/// What the module tells the user about the audio. The tab and the Settings rows read this one object, so they never
/// disagree, and the Settings rows can read it whether or not the module runs.
@Observable
final class EqualizerStatus {
    /// Where the engine is, as far as the module knows.
    enum Phase: Equatable {
        /// The switch is off, or the module is not running: no engine.
        case off
        /// On and running, with no device playing.
        case waiting
        /// On and running, tuning these devices.
        case processing([String])
        /// On, but the engine is stopped because macOS probably does not let MyNotch record system audio. A tap without
        /// the permission still mutes its device, so the original sound plays only while the engine is stopped.
        case needsPermission
        /// On, but the engine is stopped because a device could not be set up. The reason is the engine's own.
        case failed(String)
    }

    /// The one message the user gets, which is not always the whole phase: eqMac outranks "what is playing".
    enum Line: Equatable {
        case off
        case waiting
        case processing([String])
        case eqMac
        case permission
        case failed(String)

        var text: String {
            switch self {
            case .off: "EQ đang tắt"
            case .waiting: "EQ đang chờ âm thanh"
            case .processing(let names): "Đang chỉnh: " + names.joined(separator: ", ")
            case .eqMac: "eqMac đang chạy: hai bộ EQ sẽ chồng lên nhau. Thoát eqMac để dùng EQ của MyNotch."
            case .permission: "EQ tạm dừng: chưa có quyền ghi âm thanh. Tiếng vẫn phát bình thường."
            case .failed(let reason): "EQ không chạy được: " + reason
            }
        }

        /// What the user can do about it, in the order the buttons stand.
        var actions: [Action] {
            switch self {
            case .permission: [.openSettings, .retry]
            case .failed: [.retry]
            case .off, .waiting, .processing, .eqMac: []
            }
        }

        /// Something that costs the user the EQ or a clean sound, as opposed to a report of what is going on.
        var isWarning: Bool {
            switch self {
            case .permission, .failed, .eqMac: true
            case .off, .waiting, .processing: false
            }
        }
    }

    enum Action: Hashable {
        case openSettings
        case retry

        var title: String {
            switch self {
            case .openSettings: "Mở System Settings"
            case .retry: "Thử lại"
            }
        }
    }

    var phase = Phase.off
    /// Looked for when the module starts and whenever the tab opens, not all the time.
    var eqMacRunning = false

    /// Running, which is the only time the engine's reports about devices mean anything.
    var isRunning: Bool {
        switch phase {
        case .waiting, .processing: true
        case .off, .needsPermission, .failed: false
        }
    }

    /// Stopped for a reason the user can clear with "Thử lại".
    var isPaused: Bool {
        switch phase {
        case .needsPermission, .failed: true
        case .off, .waiting, .processing: false
        }
    }

    /// A failure to act on comes before the warning about eqMac, and that before what is playing; eqMac matters only while
    /// this EQ is on.
    var line: Line {
        switch phase {
        case .off: .off
        case .needsPermission: .permission
        case .failed(let reason): .failed(reason)
        case .waiting: eqMacRunning ? .eqMac : .waiting
        case .processing(let names): eqMacRunning ? .eqMac : .processing(names)
        }
    }
}
