import Foundation

nonisolated enum PortProbeResult: Equatable, Sendable {
    case free
    /// Something holds it, but not a process this app can see.
    case inUse
    /// The system would not say (a port below 1024 needs more rights than the user has).
    case unknown
}

nonisolated struct PortProbeOutcome: Equatable, Sendable {
    let port: UInt16
    let result: PortProbeResult
}

/// Asks the system whether a port can be taken, for the ports that no process of the user shows up for.
nonisolated protocol PortProbe: Sendable {
    func probe(port: UInt16) -> PortProbeResult
}

/// "Cổng nào đang bị chiếm?": what is on the port a user typed.
nonisolated enum PortQuickCheck {
    enum Answer: Equatable {
        case empty
        case invalid
        /// The owner, and how many more rows the port has (several workers can share one).
        case owner(PortEntry, others: Int)
        case free(UInt16)
        case busyUnseen(UInt16)
        case unseen(UInt16)
        /// Not in the list, and the probe has not answered yet.
        case checking(UInt16)
    }

    /// "3000" or ":3000"; nil for anything that is not a port.
    static func port(from text: String) -> UInt16? {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(":") { trimmed.removeFirst() }
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }), let value = UInt16(trimmed), value > 0 else { return nil }
        return value
    }

    /// The owner from `entries` when there is one, TCP first. Otherwise what the probe found out: a port nobody of the user's holds is
    /// not necessarily free (root or another user can), so "trống" is only said when the system agrees.
    static func answer(query: String, entries: [PortEntry], probe: PortProbeOutcome?) -> Answer {
        if query.trimmingCharacters(in: .whitespaces).isEmpty { return .empty }
        guard let port = port(from: query) else { return .invalid }
        let holders = entries.filter { $0.port == port }.sorted { ($0.proto, $0.pid) < ($1.proto, $1.pid) }
        if let first = holders.first { return .owner(first, others: holders.count - 1) }
        guard let probe, probe.port == port else { return .checking(port) }
        switch probe.result {
        case .free: return .free(port)
        case .inUse: return .busyUnseen(port)
        case .unknown: return .unseen(port)
        }
    }
}

extension PortQuickCheck.Answer {
    var message: String? {
        switch self {
        case .empty: nil
        case .invalid: "Nhập số cổng từ 1 đến 65535"
        case .owner(let entry, let others):
            "Cổng \(entry.port): \(entry.process.fullName) · PID \(entry.pid)" + (others > 0 ? " và \(others) nữa" : "")
        case .free(let port): "Cổng \(port) trống"
        case .busyUnseen(let port): "Cổng \(port) đang bị chiếm, nhưng không đọc được tiến trình (của hệ thống hoặc người dùng khác)"
        case .unseen(let port): "Không thấy tiến trình nào của bạn dùng cổng \(port)"
        case .checking: nil
        }
    }
}
