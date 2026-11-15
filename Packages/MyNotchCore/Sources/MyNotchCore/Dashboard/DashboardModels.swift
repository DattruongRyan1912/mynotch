import Foundation
import Observation

/// The visual severity or health status of a metric or module snapshot.
public enum DashboardStatusLevel: String, Sendable, Equatable {
    case normal
    case success
    case warning
    case critical
}

/// The value represented by a dashboard metric item.
public enum DashboardMetricValue: Sendable, Equatable {
    case text(String)
    case number(Double, unit: String)
    case progress(current: Double, total: Double, label: String)
    case status(DashboardStatusLevel, String)
    case count(Int)

    public var displayString: String {
        switch self {
        case .text(let str): return str
        case .number(let val, _):
            if val.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(val))"
            } else {
                return String(format: "%.1f", val)
            }
        case .progress(_, _, let label): return label
        case .status(_, let desc): return desc
        case .count(let c): return "\(c)"
        }
    }

    public var unitString: String? {
        switch self {
        case .number(_, let u): return u.isEmpty ? nil : u
        default: return nil
        }
    }

    public var numberValue: Double? {
        switch self {
        case .number(let val, _): return val
        case .count(let c): return Double(c)
        case .progress(let cur, _, _): return cur
        default: return nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .text(let str):
            let lower = str.lowercased()
            if lower == "true" || lower == "bật" || lower == "yes" || lower == "đang phát" { return true }
            if lower == "false" || lower == "tắt" || lower == "no" || lower == "tạm dừng" { return false }
            return nil
        default: return nil
        }
    }
}

/// A discrete metric displayed in a module card or dashboard widget.
public struct DashboardMetric: Identifiable, Sendable, Equatable {
    public var id: String { name }
    public let name: String
    public let value: DashboardMetricValue
    public let systemImage: String?

    public init(name: String, value: DashboardMetricValue, systemImage: String? = nil) {
        self.name = name
        self.value = value
        self.systemImage = systemImage
    }
}

/// A point-in-time snapshot of a module's telemetry and activity for the dashboard.
public struct DashboardSnapshot: Identifiable, Sendable, Equatable {
    public var id: ModuleID { moduleID }
    public let moduleID: ModuleID
    public let title: String
    public let systemImage: String
    public let status: DashboardStatusLevel
    public let summary: String
    public let metrics: [DashboardMetric]
    public let timestamp: Date

    public init(
        moduleID: ModuleID,
        title: String,
        systemImage: String,
        status: DashboardStatusLevel = .normal,
        summary: String,
        metrics: [DashboardMetric] = [],
        timestamp: Date = .now
    ) {
        self.moduleID = moduleID
        self.title = title
        self.systemImage = systemImage
        self.status = status
        self.summary = summary
        self.metrics = metrics
        self.timestamp = timestamp
    }

    public func metric(named query: String) -> DashboardMetric? {
        metrics.first { $0.name.localizedCaseInsensitiveContains(query) }
    }
}

/// Overall health summary of the MyNotch application and modules.
public struct DashboardHealthSummary: Sendable, Equatable {
    public var totalModules: Int
    public var activeModules: Int
    public var pausedModules: Int
    public var disabledModules: Int
    public var totalStorageBytes: Int64
    public var hasWarnings: Bool

    public init(
        totalModules: Int = 0,
        activeModules: Int = 0,
        pausedModules: Int = 0,
        disabledModules: Int = 0,
        totalStorageBytes: Int64 = 0,
        hasWarnings: Bool = false
    ) {
        self.totalModules = totalModules
        self.activeModules = activeModules
        self.pausedModules = pausedModules
        self.disabledModules = disabledModules
        self.totalStorageBytes = totalStorageBytes
        self.hasWarnings = hasWarnings
    }
}

/// Navigation section inside the Dashboard window.
public enum DashboardSection: String, CaseIterable, Identifiable, Sendable {
    case overview = "Tổng quan"
    case hardware = "Hệ thống & Phần cứng"
    case productivity = "Năng suất & Thời gian"
    case cleaner = "Dọn dẹp & Tối ưu"
    case modules = "Quản lý Mô-đun"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .hardware: return "cpu"
        case .productivity: return "checklist"
        case .cleaner: return "trash"
        case .modules: return "shippingbox"
        }
    }
}

/// Protocol that modules implement to supply rich telemetry to the Dashboard.
public protocol DashboardReporting: AnyObject, Sendable {
    @MainActor
    func dashboardSnapshot() -> DashboardSnapshot

    /// Informs the module whether the dashboard is actively presenting on screen.
    @MainActor
    func setDashboardActive(_ active: Bool)
}

extension DashboardReporting {
    public func setDashboardActive(_ active: Bool) {}
}
