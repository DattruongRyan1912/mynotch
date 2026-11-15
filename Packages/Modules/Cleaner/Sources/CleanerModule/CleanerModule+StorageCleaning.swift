import AppKit
import Foundation
import MyNotchCore

extension CleanerModule: StorageCleaning {
    public func storageCategories(storage: ModuleStorage) async -> [StorageCategory] {
        let runningApps = NSWorkspace.shared.runningApplications
        let runningIDs = Set(runningApps.compactMap(\.bundleIdentifier))
        let runningNames = Set(runningApps.compactMap(\.localizedName))

        let scanResult = await SystemCleanScanner.scan(
            home: FileManager.default.homeDirectoryForCurrentUser,
            runningIDs: runningIDs,
            runningNames: runningNames
        )

        self.cachedPlans = scanResult.plans
        return scanResult.categories
    }

    public func clean(categoryID: String, storage: ModuleStorage) async -> Int64 {
        let plan: DeletionPlan
        if let cached = cachedPlans[categoryID] {
            plan = cached
        } else {
            // Nếu không có trong cache, quét nhanh lại
            let runningApps = NSWorkspace.shared.runningApplications
            let runningIDs = Set(runningApps.compactMap(\.bundleIdentifier))
            let runningNames = Set(runningApps.compactMap(\.localizedName))

            let fresh = await SystemCleanScanner.scan(
                home: FileManager.default.homeDirectoryForCurrentUser,
                runningIDs: runningIDs,
                runningNames: runningNames
            )
            self.cachedPlans = fresh.plans
            guard let freshPlan = fresh.plans[categoryID] else { return 0 }
            plan = freshPlan
        }

        // Với system & developer junk, dọn dẹp trực tiếp bằng FileManager qua mode .unlink
        // Chạy trên background task để tránh block MainActor khi dung lượng thư mục lớn
        let targetPlan = plan
        let result = await Task.detached(priority: .userInitiated) {
            DeletionExecutor.execute(
                plan: targetPlan,
                mode: .unlink
            )
        }.value

        cachedPlans.removeValue(forKey: categoryID)
        return result.freedBytes
    }
}
