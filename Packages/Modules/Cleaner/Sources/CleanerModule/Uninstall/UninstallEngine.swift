import AppKit
import Foundation

/// Abstract protocol to check running application instances (allows unit test injection).
nonisolated public protocol RunningAppChecking: Sendable {
    func runningApplications(bundleID: String) -> [String]
}

/// Default implementation using macOS NSWorkspace and NSRunningApplication.
nonisolated public struct DefaultRunningAppChecker: RunningAppChecking {
    public init() {}

    public func runningApplications(bundleID: String) -> [String] {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        return apps.compactMap { $0.localizedName }
    }
}

/// Engine orchestrating the safe uninstallation of an application package and its residuals (NC-MYN-029).
nonisolated public enum UninstallEngine {
    public enum UninstallError: Error, LocalizedError, Equatable {
        case appRunning([String])
        case appDeletionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .appRunning(let names):
                return "Ứng dụng đang chạy (\(names.joined(separator: ", "))). Vui lòng đóng ứng dụng trước khi gỡ bỏ."
            case .appDeletionFailed(let err):
                return "Không thể di chuyển ứng dụng vào Thùng rác: \(err)"
            }
        }
    }

    /// Assembles an immutable DeletionPlan for an app bundle and its approved residuals.
    public static func makePlan(
        info: AppBundleInfo,
        selectedResiduals: [Residual]
    ) -> DeletionPlan {
        var items: [PlannedItem] = []

        // 1. Target application package (.app)
        if let appItem = PlannedItem.capture(url: info.url, bytes: info.sizeBytes, ownerBundleID: info.bundleID) {
            items.append(appItem)
        }

        // 2. Selected residuals (excluding locked or denied items)
        for res in selectedResiduals where !res.locked && !res.deniedFDA {
            if let item = PlannedItem.capture(url: res.url, bytes: res.bytes, ownerBundleID: info.bundleID) {
                items.append(item)
            }
        }

        return DeletionPlan(items: items)
    }

    /// Executes the uninstallation plan: Trashes .app first, stops on error, then trashes residuals.
    public static func execute(
        plan: DeletionPlan,
        runningChecker: RunningAppChecking = DefaultRunningAppChecker(),
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        trasher: DeletionExecutor.Trasher? = nil
    ) throws -> ExecutionReport {
        // Step 1: Check running instances
        var allRunning: [String] = []
        for item in plan.items {
            if let owner = item.ownerBundleID {
                let running = runningChecker.runningApplications(bundleID: owner)
                allRunning.append(contentsOf: running)
            }
        }
        if !allRunning.isEmpty {
            throw UninstallError.appRunning(Array(Set(allRunning)))
        }

        guard let appItem = plan.items.first(where: { $0.url.pathExtension.lowercased() == "app" }) else {
            // If no .app item, just execute whatever residual plan is provided
            return DeletionExecutor.execute(plan: plan, mode: .trash, home: home, trasher: trasher)
        }

        // Step 2: Delete .app first
        let singleAppPlan = DeletionPlan(items: [appItem])
        let appReport = DeletionExecutor.execute(plan: singleAppPlan, mode: .trash, home: home, trasher: trasher)

        if let failure = appReport.failed.first {
            // STOP! Do not touch residuals if .app cannot be moved to trash
            throw UninstallError.appDeletionFailed(failure.error)
        }

        var finalReport = appReport

        // Step 3: Delete remaining residuals
        let residualItems = plan.items.filter { $0.url != appItem.url }
        if !residualItems.isEmpty {
            let residualPlan = DeletionPlan(items: residualItems)
            let resReport = DeletionExecutor.execute(plan: residualPlan, mode: .trash, home: home, trasher: trasher)

            finalReport.removed.append(contentsOf: resReport.removed)
            finalReport.resultingTrashURLs.append(contentsOf: resReport.resultingTrashURLs)
            finalReport.freedBytes += resReport.freedBytes
            finalReport.skippedChanged += resReport.skippedChanged
            finalReport.skippedRunning += resReport.skippedRunning
            finalReport.failed.append(contentsOf: resReport.failed)
        }

        return finalReport
    }
}
