import Foundation

nonisolated enum StopFailure: Equatable, Sendable {
    /// The system refused the signal.
    case denied
    /// The process is not the one that was shown: another one took its pid.
    case changed
    /// Still there after SIGKILL.
    case stuck

    var message: String {
        switch self {
        case .denied: "Hệ thống không cho dừng tiến trình này."
        case .changed: "Tiến trình đã khác so với lúc nãy, hãy chọn lại."
        case .stuck: "Tiến trình vẫn chưa thoát, kể cả sau khi buộc dừng."
        }
    }
}

/// Where stopping a process has got to. Each step that sends a signal is the user's own click.
nonisolated enum StopPhase: Equatable, Sendable {
    /// Asked, and waiting for "Dừng" or "Huỷ"; nothing was sent.
    case confirming
    /// SIGTERM sent; the process has `StopFlow.grace` to leave.
    case stopping
    /// Still alive after the grace: "Buộc dừng" is offered. Nothing more is sent until it is clicked.
    case stillRunning
    /// SIGKILL sent.
    case forcing
    case refused(StopRefusal)
    case failed(StopFailure)

    /// Whether the tab must stay open for the user to answer, rather than the pointer leaving closing it.
    var needsAnswer: Bool {
        switch self {
        case .confirming, .stillRunning, .refused, .failed: true
        case .stopping, .forcing: false
        }
    }

    /// Whether a signal is on its way or has just gone, so another request for the same process waits.
    var isBusy: Bool { self == .stopping || self == .forcing }
}

/// One stop in progress, for the row it was asked on.
nonisolated struct StopFlow: Equatable, Sendable {
    /// How long a process gets to leave after SIGTERM before "Buộc dừng" is offered.
    static let grace = Duration.seconds(3)
    /// How long a process gets to leave after SIGKILL before it is called stuck.
    static let killGrace = Duration.seconds(1)

    let entry: PortEntry
    var phase: StopPhase

    var message: String {
        let subject = "\(entry.process.fullName) (cổng \(entry.port))"
        switch phase {
        case .confirming: return "Dừng \(subject)?"
        case .stopping: return "Đang dừng \(subject)…"
        case .stillRunning: return "\(subject) chưa thoát."
        case .forcing: return "Đang buộc dừng \(subject)…"
        case .refused(let refusal): return refusal.message
        case .failed(let failure): return failure.message
        }
    }
}
