import Foundation
import Testing
@testable import CleanerModule

@Suite("UninstallEngine Execution Pipeline Tests")
struct UninstallEngineTests {
    struct MockRunningAppChecker: RunningAppChecking {
        let running: [String]
        func runningApplications(bundleID: String) -> [String] {
            return running
        }
    }

    @Test("makePlan lọc bỏ các residual bị locked hoặc denied FDA")
    func testMakePlanFiltering() {
        let appURL = URL(filePath: "/Applications/TestApp.app")
        let info = AppBundleInfo(
            url: appURL,
            bundleID: "com.example.test",
            displayName: "TestApp",
            version: "1.0",
            sizeBytes: 5000
        )

        let safeResidual = Residual(
            url: URL(filePath: "/Users/test/Library/Caches/com.example.test"),
            tier: .tier1,
            bytes: 200,
            selectedByDefault: true,
            locked: false,
            deniedFDA: false
        )

        let lockedResidual = Residual(
            url: URL(filePath: "/Users/test/Library/Application Support/ExampleVendor"),
            tier: .tier3,
            bytes: 1000,
            selectedByDefault: false,
            locked: true,
            deniedFDA: false
        )

        let deniedResidual = Residual(
            url: URL(filePath: "/Users/test/Library/Safari/com.example.test"),
            tier: .tier1,
            bytes: 0,
            selectedByDefault: false,
            locked: false,
            deniedFDA: true
        )

        let plan = UninstallEngine.makePlan(
            info: info,
            selectedResiduals: [safeResidual, lockedResidual, deniedResidual]
        )

        // Không được chứa locked và denied
        let plannedPaths = plan.items.map(\.path)
        #expect(!plannedPaths.contains(lockedResidual.url.path))
        #expect(!plannedPaths.contains(deniedResidual.url.path))
    }

    @Test("execute ném lỗi khi ứng dụng đang chạy")
    func testExecuteFailsWhenAppIsRunning() {
        let info = AppBundleInfo(
            url: URL(filePath: "/Applications/RunningApp.app"),
            bundleID: "com.example.running",
            displayName: "RunningApp",
            version: "1.0",
            sizeBytes: 100
        )

        let plan = DeletionPlan(items: [
            PlannedItem(
                url: info.url,
                kind: .directory,
                dev: 1,
                ino: 2,
                mtimeNs: 3,
                bytes: 100,
                canonicalParent: "/Applications",
                ownerBundleID: info.bundleID
            )
        ])

        let checker = MockRunningAppChecker(running: ["RunningApp"])

        #expect(throws: UninstallEngine.UninstallError.self) {
            try UninstallEngine.execute(plan: plan, runningChecker: checker)
        }
    }

    @Test("execute dừng ngay nếu xoá .app thất bại và không chạm vào residuals")
    func testExecuteStopsIfAppFails() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appURL = tempDir.appending(path: "Dummy.app")
        let residualURL = tempDir.appending(path: "residual.txt")

        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try "data".write(to: residualURL, atomically: true, encoding: .utf8)

        guard let appItem = PlannedItem.capture(url: appURL, bytes: 100, ownerBundleID: "com.example.dummy"),
              let resItem = PlannedItem.capture(url: residualURL, bytes: 50, ownerBundleID: "com.example.dummy") else {
            Issue.record("Không thể capture planned items")
            return
        }

        let plan = DeletionPlan(items: [appItem, resItem])

        // Fake trasher ném lỗi khi xoá .app
        let failingTrasher: DeletionExecutor.Trasher = { url in
            if url.pathExtension.lowercased() == "app" {
                throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
            }
            return nil
        }

        #expect(throws: UninstallEngine.UninstallError.self) {
            try UninstallEngine.execute(
                plan: plan,
                runningChecker: MockRunningAppChecker(running: []),
                home: tempDir,
                trasher: failingTrasher
            )
        }

        // Tệp residual vẫn còn nguyên trên đĩa
        #expect(FileManager.default.fileExists(atPath: residualURL.path))
    }
}
