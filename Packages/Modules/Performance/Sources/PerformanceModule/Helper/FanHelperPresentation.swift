import Foundation

/// What the tab and Settings say about the helper, decided in one place from where it is.
nonisolated struct FanHelperPresentation: Equatable, Sendable {
    /// For Settings, where there is room.
    let status: String
    /// For the tab, where there is a line.
    let shortStatus: String
    /// The marker's tone: green when running, orange when the user has to act, red on an error; nil when nothing is known.
    let tone: Tone?
    /// What the main button does, nil when there is nothing to press.
    let primary: FanHelperAction?
    /// Whether "Gỡ helper" is offered.
    let canUninstall: Bool
    let isBusy: Bool
    /// "Thoát Macs Fan Control…" while that app is running, for the day the fans are controlled from here.
    let warning: String?

    static let macsFanControlWarning = "Thoát Macs Fan Control trước khi điều khiển quạt"
    /// Where the full rows are: the menu bar icon's "Open Settings…" (⌘,), then this.
    static let settingsPath = "Cài đặt MyNotch → Mô-đun → Hiệu năng → Điều khiển quạt"

    /// What the tab's line says when the pointer rests on it: the full status, and where to find the rest.
    var tooltip: String { "\(status)\n\(Self.settingsPath)" }

    init(phase: FanHelperPhase, macsFanControlRunning: Bool) {
        warning = macsFanControlRunning ? Self.macsFanControlWarning : nil
        isBusy = if case .busy = phase { true } else { false }
        switch phase {
        case .unknown:
            (status, shortStatus, tone, primary, canUninstall) = ("Đang kiểm tra…", "đang kiểm tra", nil, nil, false)
        case .notInstalled:
            (status, shortStatus, tone, primary, canUninstall) = ("Chưa cài", "chưa cài", nil, .install, false)
        case .needsApproval:
            (status, shortStatus, tone, primary, canUninstall) =
                ("Cần cho phép trong Cài đặt hệ thống", "cần cho phép", .caution, .openSettings, true)
        case let .running(info):
            (status, shortStatus, tone, primary, canUninstall) =
                ("Đang chạy (phiên bản \(info.version), quyền root)", "đang chạy", .normal, nil, true)
        case let .unreachable(reason):
            (status, shortStatus, tone, primary, canUninstall) = ("Lỗi: không kết nối được helper (\(reason))", "lỗi", .critical, .retry, true)
        case let .failed(reason):
            (status, shortStatus, tone, primary, canUninstall) = ("Lỗi: \(reason)", "lỗi", .critical, .retry, true)
        case let .busy(operation):
            let text = switch operation {
            case .installing: "Đang cài…"
            case .removing: "Đang gỡ…"
            case .updating: "Đang cập nhật helper…"
            }
            (status, shortStatus, tone, primary, canUninstall) = (text, text.lowercasedFirst, .caution, nil, false)
        }
    }
}

nonisolated extension FanHelperAction {
    /// The button's label in Settings.
    var title: String {
        switch self {
        case .install: "Cài helper điều khiển quạt"
        case .openSettings: "Mở Cài đặt"
        case .retry: "Thử lại"
        }
    }

    /// The button's label in the tab, where a line is all there is.
    var compactTitle: String {
        switch self {
        case .install: "Cài helper"
        case .openSettings: "Cài đặt"
        case .retry: "Thử lại"
        }
    }
}

private nonisolated extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

/// The helper's reading of the fans next to the app's own, to see that they agree.
nonisolated struct FanComparison: Equatable, Sendable {
    let lines: [String]
    let failure: String?

    init(helper: [FanHelperFanInfo], app: [FanReading]) {
        failure = nil
        lines = helper.map { fan in
            let appRPM = app.first { $0.index == fan.index }.map { ThermalFormat.rpm($0.rpm) } ?? "—"
            return "Quạt \(fan.index + 1): helper \(ThermalFormat.rpm(fan.rpm)) · app \(appRPM) vòng/phút · \(Self.mode(fan.mode))"
        }
    }

    init(failure: String) {
        lines = []
        self.failure = failure
    }

    /// The SMC's fan mode: 0 is automatic.
    static func mode(_ value: Double) -> String {
        switch value {
        case ..<0: "chế độ không rõ"
        case 0: "tự động"
        default: "thủ công (\(Int(value)))"
        }
    }
}
