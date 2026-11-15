import AppKit
import Foundation
import Testing
@testable import CleanerModule
import MyNotchCore

@Suite struct MyNotchResourceCleanerTests {
    @Test func testScanAndCleanAppCachesAndLogsSkipsModulesSubfolderAndPreservesDurableSupport() async throws {
        let tempHome = FileManager.default.temporaryDirectory.appending(path: "MyNotchTestHome-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let bundleID = "io.lucasvu.mynotch"
        let appCachesDir = tempHome.appending(path: "Library/Caches/\(bundleID)")
        let fsCachedDataDir = appCachesDir.appending(path: "fsCachedData")
        let modulesDir = appCachesDir.appending(path: "Modules/clipboard")
        let appLogsDir = tempHome.appending(path: "Library/Logs/MyNotch")
        let appSupportDir = tempHome.appending(path: "Library/Application Support/\(bundleID)/Modules/clipboard")

        try FileManager.default.createDirectory(at: fsCachedDataDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modulesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appLogsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)

        let chunk1URL = fsCachedDataDir.appending(path: "chunk1.bin")
        let thumbURL = modulesDir.appending(path: "thumb.png")
        let logURL = appLogsDir.appending(path: "session.log")
        let historyURL = appSupportDir.appending(path: "history.json")

        try Data(repeating: 0x41, count: 2048).write(to: chunk1URL)
        try Data(repeating: 0x42, count: 4096).write(to: thumbURL)
        try Data(repeating: 0x43, count: 1024).write(to: logURL)
        try Data(repeating: 0x44, count: 512).write(to: historyURL)

        // 1. Quét tài nguyên
        let scan = await MyNotchResourceCleaner.scanAppCachesAndLogs(home: tempHome, bundleID: bundleID)
        #expect(scan.appCacheBytes == 2048) // Bỏ qua 4096 bytes của Modules/
        #expect(scan.appLogBytes == 1024)
        #expect(scan.totalBytes == 3072)

        // 2. Dọn tài nguyên
        let freed = await MyNotchResourceCleaner.cleanAppCachesAndLogs(home: tempHome, bundleID: bundleID)
        #expect(freed == 3072)

        // 3. Kiểm chứng: Modules và Application Support còn nguyên vẹn
        #expect(FileManager.default.fileExists(atPath: thumbURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: historyURL.path(percentEncoded: false)))

        // 4. Kiểm chứng: fsCachedData và session.log đã bị xoá
        #expect(!FileManager.default.fileExists(atPath: chunk1URL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: logURL.path(percentEncoded: false)))
    }

    @Test func testCleanAppCachesRefusesSymlinkEscapeAndHandlesMissingFolders() async throws {
        let tempHome = FileManager.default.temporaryDirectory.appending(path: "MyNotchSymlinkHome-\(UUID().uuidString)")
        let outsideDir = FileManager.default.temporaryDirectory.appending(path: "MyNotchOutside-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: tempHome)
            try? FileManager.default.removeItem(at: outsideDir)
        }

        // Kiểm tra khi thư mục chưa tồn tại
        let scanEmpty = await MyNotchResourceCleaner.scanAppCachesAndLogs(home: tempHome, bundleID: "nonexistent.app")
        #expect(scanEmpty.totalBytes == 0)
        let freedEmpty = await MyNotchResourceCleaner.cleanAppCachesAndLogs(home: tempHome, bundleID: "nonexistent.app")
        #expect(freedEmpty == 0)

        // Tạo thư mục ngoài và file bí mật
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        let secretFile = outsideDir.appending(path: "secret.txt")
        try Data("secret-content".utf8).write(to: secretFile)

        // Tạo symlink từ Library/Logs/MyNotch trỏ ra ngoài
        let logsDir = tempHome.appending(path: "Library/Logs")
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let symlinkLog = logsDir.appending(path: "MyNotch")
        try FileManager.default.createSymbolicLink(at: symlinkLog, withDestinationURL: outsideDir)

        let scan = await MyNotchResourceCleaner.scanAppCachesAndLogs(home: tempHome, bundleID: "io.lucasvu.mynotch")
        #expect(scan.appLogBytes == 0)

        let freed = await MyNotchResourceCleaner.cleanAppCachesAndLogs(home: tempHome, bundleID: "io.lucasvu.mynotch")
        #expect(freed == 0)

        // File bí mật bên ngoài còn nguyên vẹn
        #expect(FileManager.default.fileExists(atPath: secretFile.path(percentEncoded: false)))
    }

    @Test func testDefaultSafeSelectedIDsExcludesTrashEmptyAndRunningXcodeDerivedData() {
        let categories: [StorageCategory] = [
            StorageCategory(id: "cleaner.dev.deriveddata", title: "Xcode DerivedData", bytes: 500_000, keeps: nil, canClean: true, scope: .developer),
            StorageCategory(id: "cleaner.dev.npm", title: "npm Cache", bytes: 200_000, keeps: nil, canClean: true, scope: .developer),
            StorageCategory(id: "cleaner.dev.cargo", title: "Cargo Cache", bytes: 0, keeps: nil, canClean: false, scope: .developer),
            StorageCategory(id: "cleaner.system.usercaches", title: "Bộ nhớ tạm ứng dụng", bytes: 100_000, keeps: nil, canClean: true, scope: .system),
            StorageCategory(id: "cleaner.system.trash", title: "Thùng rác", bytes: 900_000, keeps: nil, canClean: true, scope: .system, caution: "Cảnh báo xoá vĩnh viễn"),
        ]

        // Khi Xcode đang chạy: loại bỏ deriveddata, trash, và mục 0 byte
        let withXcode = MyNotchResourceCleaner.defaultSafeSelectedIDs(categories: categories, runningBundleIDs: ["com.apple.dt.Xcode"])
        #expect(withXcode == Set(["cleaner.dev.npm", "cleaner.system.usercaches"]))

        // Khi Xcode không chạy: bao gồm deriveddata, loại bỏ trash và mục 0 byte
        let withoutXcode = MyNotchResourceCleaner.defaultSafeSelectedIDs(categories: categories, runningBundleIDs: [])
        #expect(withoutXcode == Set(["cleaner.dev.deriveddata", "cleaner.dev.npm", "cleaner.system.usercaches"]))
    }

    @Test func testRelieveProcessMemoryRunsOffMainThreadAndReadsRealFootprint() async {
        // 1. Mocked deterministic run
        let reportMock = await MyNotchResourceCleaner.relieveProcessMemory(
            relieve: {
                #expect(!Thread.isMainThread)
                return 131_072
            },
            footprintProvider: { 52_428_800 }
        )
        #expect(reportMock.reclaimedZoneBytes == 131_072)
        #expect(reportMock.footprintAfterBytes == 52_428_800)

        // 2. Live Darwin run
        let reportLive = await MyNotchResourceCleaner.relieveProcessMemory()
        #expect(reportLive.reclaimedZoneBytes >= 0)
        #expect(reportLive.footprintAfterBytes > 1_000_000)
    }

    @Test func testCleanAppCachesDoesNotCountUnremovableFiles() async throws {
        let tempHome = FileManager.default.temporaryDirectory.appending(path: "MyNotchLockedHome-\(UUID().uuidString)")
        defer {
            let logsDir = tempHome.appending(path: "Library/Logs/MyNotch")
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: logsDir.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: tempHome)
        }

        let bundleID = "io.lucasvu.mynotch"
        let logsDir = tempHome.appending(path: "Library/Logs/MyNotch")
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let lockedFile = logsDir.appending(path: "locked.log")
        try Data(repeating: 0x45, count: 1024).write(to: lockedFile)

        // Make parent directory read-only (0555) so deletion inside it fails with Permission Denied
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: logsDir.path(percentEncoded: false))

        let freed = await MyNotchResourceCleaner.cleanAppCachesAndLogs(home: tempHome, bundleID: bundleID)
        #expect(freed == 0) // Không cộng khống 1024 byte khi removeItem thất bại!

        // Restore permissions for cleanup
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: logsDir.path(percentEncoded: false))
    }

    @Test func testCleanFolderDoesNotTraverseOrDeleteSymlinkTargetOutsideSandbox() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appending(path: "MyNotchSymlinkTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let externalTargetDir = tempRoot.appending(path: "ExternalSecrets")
        let tempHome = tempRoot.appending(path: "Home")
        let bundleID = "io.lucasvu.mynotch"
        let appCachesDir = tempHome.appending(path: "Library/Caches/\(bundleID)")

        try FileManager.default.createDirectory(at: externalTargetDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appCachesDir, withIntermediateDirectories: true)

        let secretFile = externalTargetDir.appending(path: "secret.txt")
        try Data("CONFIDENTIAL_DATA".utf8).write(to: secretFile)

        // Tạo symlink trong Caches trỏ ra thư mục ExternalSecrets bên ngoài sandbox
        let symlinkDir = appCachesDir.appending(path: "EscapedSymlink")
        try FileManager.default.createSymbolicLink(at: symlinkDir, withDestinationURL: externalTargetDir)

        // 1. Quét không được tính dung lượng file bên trong symlink target
        let scan = await MyNotchResourceCleaner.scanAppCachesAndLogs(home: tempHome, bundleID: bundleID)
        #expect(scan.totalBytes == 0)

        // 2. Dọn dẹp chỉ unlink file symlink, không được xoá file trong ExternalSecrets
        let freed = await MyNotchResourceCleaner.cleanAppCachesAndLogs(home: tempHome, bundleID: bundleID)
        #expect(freed == 0)

        // 3. Đối soát: File secret bên ngoài vẫn tồn tại nguyên vẹn!
        #expect(FileManager.default.fileExists(atPath: secretFile.path(percentEncoded: false)))
    }
}
