import EqualizerAudio
import Observation

/// What the module tells the user about the audio. The tab and the Settings rows read this one object, so they never
/// disagree, and the Settings rows can read it whether or not the module runs.
@Observable
public final class EqualizerStatus {
    /// Where the engine is, as far as the module knows.
    public enum Phase: Equatable {
        /// The switch is off, or the module is not running: no engine.
        case off
        /// On and running, with no device playing.
        case waiting
        /// On and running, tuning these devices.
        case processing([String])
        /// On, but the engine is stopped because macOS probably does not let MyNotch record system audio. A tap without
        /// the permission still mutes its device, so the original sound plays only while the engine is stopped.
        case needsPermission
        /// On, but the engine is stopped because every device that was to be tuned could not be set up. The reason is the
        /// engine's: "<device>: <why>".
        case failed(String)
    }

    /// The one message the user gets, which is not always the whole phase: eqMac outranks "what is playing".
    public enum Line: Equatable {
        case off
        case waiting
        case processing([String])
        case eqMac
        case permission
        case failed(String)

        public var text: String {
            switch self {
            case .off: "EQ đang tắt"
            case .waiting: "EQ đang chờ âm thanh"
            case .processing(let names): "Đang chỉnh: " + names.joined(separator: ", ")
            case .eqMac: "eqMac đang chạy: hai bộ EQ sẽ chồng lên nhau. Thoát eqMac để dùng EQ của MyNotch."
            case .permission: "EQ tạm dừng: chưa có quyền ghi âm thanh. Tiếng vẫn phát bình thường."
            case .failed(let reason): "Không chỉnh được " + reason
            }
        }

        /// What the user can do about it, in the order the buttons stand.
        public var actions: [Action] {
            switch self {
            case .permission: [.openSettings, .retry]
            case .failed: [.retry]
            case .off, .waiting, .processing, .eqMac: []
            }
        }

        /// Something that costs the user the EQ or a clean sound, as opposed to a report of what is going on.
        public var isWarning: Bool {
            switch self {
            case .permission, .failed, .eqMac: true
            case .off, .waiting, .processing: false
            }
        }
    }

    public enum Action: Hashable {
        case openSettings
        case retry

        public var title: String {
            switch self {
            case .openSettings: "Mở System Settings"
            case .retry: "Thử lại"
            }
        }
    }

    public var phase = Phase.off
    /// Devices the engine gave up on while it keeps tuning the others, in the order reported, each "<device>: <why>". A
    /// device that is tuned again drops out; "Thử lại" and switching the EQ off clear the lot.
    public var failures: [String] = []
    /// Looked for when the module starts and whenever the tab opens, not all the time.
    public var eqMacRunning = false
    /// Real-time audio device telemetries from CoreAudio pipeline
    public var activeDeviceTelemetries: [EQDeviceTelemetry] = []

    public init() {}

    /// Running, which is the only time the engine's reports about devices mean anything.
    public var isRunning: Bool {
        switch phase {
        case .waiting, .processing: true
        case .off, .needsPermission, .failed: false
        }
    }

    /// Stopped for a reason the user can clear with "Thử lại".
    public var isPaused: Bool {
        switch phase {
        case .needsPermission, .failed: true
        case .off, .waiting, .processing: false
        }
    }

    /// The devices being tuned now.
    public var tunedDevices: [String] {
        if case .processing(let names) = phase { names } else { [] }
    }

    /// Something "Thử lại" can undo: the engine is stopped for a reason, or a device was given up on.
    public var canRetry: Bool { isPaused || !failures.isEmpty }

    /// Everything back to "no engine": the switch is off, or the module stops.
    public func reset() {
        phase = .off
        failures = []
        activeDeviceTelemetries = []
    }

    /// A failure to act on comes before the warning about eqMac, and that before what is playing; eqMac matters only while
    /// this EQ is on. A device that failed is the news even while the others run.
    public var line: Line {
        switch phase {
        case .off: .off
        case .needsPermission: .permission
        case .failed(let reason): .failed(reason)
        case .waiting, .processing:
            if let reason = failures.first {
                .failed(reason)
            } else if eqMacRunning {
                .eqMac
            } else if case .processing(let names) = phase {
                .processing(names)
            } else {
                .waiting
            }
        }
    }
}
