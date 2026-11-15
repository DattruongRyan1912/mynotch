import Foundation
import Testing
@testable import CleanerModule

@Suite("ResidualScanner Leftovers Detection Tests")
struct ResidualScannerTests {
    @Test("Nhận diện chính xác Tier 1 theo Bundle ID")
    func testTier1Detection() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Setup mock Library layout
        let cacheDir = tempDir.appending(path: "Library/Caches/com.example.mockapp")
        let prefDir = tempDir.appending(path: "Library/Preferences")
        let prefFile = prefDir.appending(path: "com.example.mockapp.plist")
        let appSupportDir = tempDir.appending(path: "Library/Application Support/com.example.mockapp")

        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: prefDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        try "dummy preference".write(to: prefFile, atomically: true, encoding: .utf8)

        let info = AppBundleInfo(
            url: URL(filePath: "/Applications/MockApp.app"),
            bundleID: "com.example.mockapp",
            displayName: "MockApp",
            version: "1.0",
            sizeBytes: 1024
        )

        let residuals = ResidualScanner.scan(
            info: info,
            home: tempDir,
            installedAppIDs: []
        )

        #expect(residuals.count >= 3)
        let tier1Items = residuals.filter { $0.tier == .tier1 }
        #expect(tier1Items.count >= 3)

        // Các mục Tier 1 mặc định được chọn
        for item in tier1Items {
            #expect(item.selectedByDefault == true)
            #expect(item.locked == false)
        }
    }

    @Test("Vendor guard bảo vệ thư mục dùng chung khi còn app cùng nhà phát triển")
    func testVendorGuardProtection() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Setup vendor folder: Google/Chrome and Google/Earth
        let googleVendorDir = tempDir.appending(path: "Library/Application Support/Google")
        try FileManager.default.createDirectory(at: googleVendorDir, withIntermediateDirectories: true)

        let info = AppBundleInfo(
            url: URL(filePath: "/Applications/Google Chrome.app"),
            bundleID: "com.google.Chrome",
            displayName: "Google Chrome",
            version: "1.0",
            sizeBytes: 1024
        )

        // Cài đặt thêm Google Earth (cùng vendor com.google.*)
        let installedIDs: Set<String> = ["com.google.Earth"]

        let residuals = ResidualScanner.scan(
            info: info,
            home: tempDir,
            installedAppIDs: installedIDs
        )

        // Thư mục Google phải bị khoá (locked = true) hoặc không xoá toàn bộ
        if let vendorResidual = residuals.first(where: { $0.url.lastPathComponent.lowercased() == "google" }) {
            #expect(vendorResidual.locked == true)
            #expect(vendorResidual.selectedByDefault == false)
        }
    }
}
