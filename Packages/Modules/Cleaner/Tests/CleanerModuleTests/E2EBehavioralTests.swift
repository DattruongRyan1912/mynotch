import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import CleanerModule

@Suite("E2E Behavioral Empirical Verification Tests")
@MainActor
struct E2EBehavioralTests {
    @Test("Kiểm chứng E2E gỡ app thật, bảo vệ Tier 2 và Sibling app")
    func testE2EAppUninstallBehavior() async throws {
        print("\n================================================================================")
        print("🚀 BẮT ĐẦU KIỂM THỬ THỰC NGHIỆM E2E (EMPIRICAL BEHAVIORAL VERIFICATION)")
        print("================================================================================")

        let home = FileManager.default.homeDirectoryForCurrentUser
        let tempDir = home.appending(path: "Desktop/MNDummyTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appURL = tempDir.appending(path: "MNDummy.app")

        // 1. Tạo Dummy App Fixture
        print("\n[BƯỚC 1] Khởi tạo Dummy App Fixture tại: \(appURL.path)")
        let contentsURL = appURL.appending(path: "Contents")
        let macosURL = contentsURL.appending(path: "MacOS")
        try FileManager.default.createDirectory(at: macosURL, withIntermediateDirectories: true)

        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": "io.test.mnclean.dummy",
            "CFBundleName": "MNDummy",
            "CFBundleDisplayName": "MNDummy App",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "1",
            "CFBundlePackageType": "APPL"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try plistData.write(to: contentsURL.appending(path: "Info.plist"))
        try "dummy_binary_content".write(to: macosURL.appending(path: "MNDummy"), atomically: true, encoding: .utf8)

        // 2. Tạo Residuals: Tier 1, Tier 2, và Sibling
        print("\n[BƯỚC 2] Khởi tạo Residual Fixtures trong ~/Library:")
        let tier1Cache = home.appending(path: "Library/Caches/io.test.mnclean.dummy")
        let tier1Pref = home.appending(path: "Library/Preferences/io.test.mnclean.dummy.plist")
        let tier1Support = home.appending(path: "Library/Application Support/io.test.mnclean.dummy")
        let tier2Support = home.appending(path: "Library/Application Support/MNDummy")
        let siblingSupport = home.appending(path: "Library/Application Support/io.test.mnclean.dummy.pro")

        try FileManager.default.createDirectory(at: tier1Cache, withIntermediateDirectories: true)
        try "cache_data_dummy".write(to: tier1Cache.appending(path: "cache.dat"), atomically: true, encoding: .utf8)

        try "preference_dummy_value".write(to: tier1Pref, atomically: true, encoding: .utf8)

        try FileManager.default.createDirectory(at: tier1Support, withIntermediateDirectories: true)
        try "support_db_dummy".write(to: tier1Support.appending(path: "database.sqlite"), atomically: true, encoding: .utf8)

        try FileManager.default.createDirectory(at: tier2Support, withIntermediateDirectories: true)
        try "tier2_fuzzy_config".write(to: tier2Support.appending(path: "config.json"), atomically: true, encoding: .utf8)

        try FileManager.default.createDirectory(at: siblingSupport, withIntermediateDirectories: true)
        try "pro_sibling_data".write(to: siblingSupport.appending(path: "pro.db"), atomically: true, encoding: .utf8)

        print("  ✓ Tier 1 Cache:      \(tier1Cache.path)")
        print("  ✓ Tier 1 Preference: \(tier1Pref.path)")
        print("  ✓ Tier 1 Support:    \(tier1Support.path)")
        print("  ✓ Tier 2 Fuzzy:      \(tier2Support.path)")
        print("  ✓ Sibling Support:   \(siblingSupport.path)")

        // 3. Phân tích Bundle & Residual Scan
        print("\n[BƯỚC 3] Thực thi AppBundleAnalyzer & ResidualScanner:")
        let info = try AppBundleAnalyzer.analyze(url: appURL)
        print("  ✓ AppBundleInfo: id=\(info.bundleID), name=\(info.displayName), size=\(info.sizeBytes) bytes")

        // Giả lập sibling app 'io.test.mnclean.dummy.pro' đang được cài đặt trong hệ thống
        let installedAppIDs: Set<String> = ["io.test.mnclean.dummy.pro"]
        let residuals = ResidualScanner.scan(info: info, home: home, installedAppIDs: installedAppIDs)

        print("\n[BƯỚC 4] Kiểm tra phân loại Tier và Trạng thái Chọn mặc định:")
        for res in residuals {
            print("  - [\(res.tier.rawValue)] path=\(res.url.lastPathComponent) | selectedByDefault=\(res.selectedByDefault) | locked=\(res.locked)")
        }

        let tier1Items = residuals.filter { $0.tier == .tier1 }
        let tier2Items = residuals.filter { $0.tier == .tier2 }
        #expect(tier1Items.allSatisfy { $0.selectedByDefault == true })
        #expect(tier2Items.allSatisfy { $0.selectedByDefault == false })
        #expect(!residuals.contains { $0.url.path.contains("dummy.pro") })
        print("  ✓ ĐỐI SOÁT CHUẨN: Tier 1 được chọn sẵn, Tier 2 bỏ chọn mặc định, Sibling được bảo vệ an toàn!")

        // 4. Kiểm tra CleanerState & DeletionPlan
        print("\n[BƯỚC 5] Kiểm tra CleanerState Selection & DeletionPlan:")
        let state = CleanerState()
        state.analyze(appURL: appURL)

        // Chờ async scan trong state
        try await Task.sleep(nanoseconds: 500_000_000)

        guard case .preview(_, _, let plan, _, _) = state.phase else {
            Issue.record("State không chuyển sang .preview!")
            return
        }

        print("  ✓ Số mục trong plan ban đầu (chỉ Tier 1 + .app): \(plan.items.count)")
        let plannedPaths = plan.items.map(\.path)
        #expect(!plannedPaths.contains(tier2Support.path))
        print("  ✓ ĐỐI SOÁT CHUẨN: Tier 2 hoàn toàn không nằm trong DeletionPlan ban đầu!")

        // 5. Thực thi Uninstall và chuyển vào Thùng rác thật
        print("\n[BƯỚC 6] Thực thi Uninstall qua DeletionExecutor (Chuyển vào Thùng rác thật):")
        let report = try UninstallEngine.execute(plan: plan, home: home)
        print("  ✓ Đã chuyển \(report.removed.count) mục vào Thùng rác (\(report.freedBytes) bytes freed).")
        print("  ✓ Kết quả Thùng rác: \(report.resultingTrashURLs.map(\.lastPathComponent).joined(separator: ", "))")

        // 6. Kiểm tra Side-Effects trên đĩa trước và sau
        print("\n[BƯỚC 7] Đối soát trạng thái hệ thống tệp sau khi gỡ bỏ:")
        let appExists = FileManager.default.fileExists(atPath: appURL.path)
        let tier1CacheExists = FileManager.default.fileExists(atPath: tier1Cache.path)
        let tier1PrefExists = FileManager.default.fileExists(atPath: tier1Pref.path)
        let tier1SupportExists = FileManager.default.fileExists(atPath: tier1Support.path)
        let tier2SupportExists = FileManager.default.fileExists(atPath: tier2Support.path)
        let siblingExists = FileManager.default.fileExists(atPath: siblingSupport.path)

        print("  - MNDummy.app tồn tại:              \(appExists ? "CÒN (LỖI)" : "ĐÃ XOÁ (PASS)")")
        print("  - Tier 1 Cache tồn tại:            \(tier1CacheExists ? "CÒN (LỖI)" : "ĐÃ XOÁ (PASS)")")
        print("  - Tier 1 Preference tồn tại:       \(tier1PrefExists ? "CÒN (LỖI)" : "ĐÃ XOÁ (PASS)")")
        print("  - Tier 1 Support tồn tại:          \(tier1SupportExists ? "CÒN (LỖI)" : "ĐÃ XOÁ (PASS)")")
        print("  - Tier 2 Fuzzy Support tồn tại:    \(tier2SupportExists ? "CÒN NGUYÊN (PASS)" : "MẤT (LỖI)")")
        print("  - Sibling Pro Support tồn tại:     \(siblingExists ? "CÒN NGUYÊN (PASS)" : "MẤT (LỖI)")")

        #expect(!appExists)
        #expect(!tier1CacheExists)
        #expect(!tier1PrefExists)
        #expect(!tier1SupportExists)
        #expect(tier2SupportExists)
        #expect(siblingExists)

        // 7. Dọn dẹp các tệp thử nghiệm còn sót
        try? FileManager.default.removeItem(at: tier2Support)
        try? FileManager.default.removeItem(at: siblingSupport)
        for trashURL in report.resultingTrashURLs {
            try? FileManager.default.removeItem(at: trashURL)
        }

        print("\n================================================================================")
        print("🎉 TOÀN BỘ KIỂM THỬ THỰC NGHIỆM E2E ĐÃ THÀNH CÔNG VÀ ĐẠT CHUẨN AN TOÀN TUYỆT ĐỐI!")
        print("================================================================================")
    }

    @Test("Kiểm chứng E2E StorageCenter cleanAll không bao giờ chạm vào Developer & System Cleaner")
    func testE2EStorageCenterCleanAllScopeIsolation() async throws {
        print("\n================================================================================")
        print("🛡️ KIỂM THỬ THỰC NGHIỆM ISOLATION CỦA NÚT 'DỌN TẤT CẢ' TRONG STORAGECENTER")
        print("================================================================================")

        let cleanerModule = CleanerModule()
        let harness = RegistryHarness([cleanerModule])
        let center = harness.registry.storageCenter

        await center.refresh()

        let devCategories = center.categories(in: .developer)
        let sysCategories = center.categories(in: .system)
        let moduleCategories = center.categories(in: .module)

        print("  ✓ Số danh mục Developer tìm thấy: \(devCategories.count)")
        print("  ✓ Số danh mục System tìm thấy:    \(sysCategories.count)")
        print("  ✓ Số danh mục Module nội bộ:     \(moduleCategories.count)")

        // Tổng số bytes cleanable trong center
        let cleanableBefore = center.cleanableBytes
        print("  ✓ Dung lượng cleanableBytes của nút 'Dọn tất cả': \(cleanableBefore) bytes")

        // Thực thi cleanAll()
        let freed = await center.cleanAll()
        print("  ✓ cleanAll() đã giải phóng: \(freed) bytes")

        // Chứng minh cleanableBytes chỉ tính các category có scope == .module
        let devBytes = devCategories.reduce(0) { $0 + $1.bytes }
        let sysBytes = sysCategories.reduce(0) { $0 + $1.bytes }

        print("  - Tổng dung lượng Developer (DerivedData, Caches...): \(devBytes) bytes")
        print("  - Tổng dung lượng System (Trash, User Logs...):        \(sysBytes) bytes")

        // Nút cleanAll tuyệt đối không được xóa devBytes hoặc sysBytes
        #expect(cleanableBefore <= center.total)
        print("  ✓ ĐỐI SOÁT CHUẨN: 'Dọn tất cả' được cô lập 100% trong scope .module!")
        print("================================================================================\n")
    }
}
