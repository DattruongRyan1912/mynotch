import Foundation
import Testing
@testable import ClipboardModule

@Suite struct CloudSyncFileStoreTests {

    // T26: An toàn filesystem (Path traversal, separator, NUL, reserved characters rejected)
    @Test func pathTraversalAndUnsafeNamesRejected() {
        #expect(!CloudSyncFileStore.isSafeFileName("../secret.txt"))
        #expect(!CloudSyncFileStore.isSafeFileName("/etc/passwd"))
        #expect(!CloudSyncFileStore.isSafeFileName("foo/bar.txt"))
        #expect(!CloudSyncFileStore.isSafeFileName("foo\0bar.txt"))
        #expect(!CloudSyncFileStore.isSafeFileName("."))
        #expect(!CloudSyncFileStore.isSafeFileName(".."))
        #expect(!CloudSyncFileStore.isSafeFileName(""))
        #expect(CloudSyncFileStore.isSafeFileName("normal_report.pdf"))
        #expect(CloudSyncFileStore.isSafeFileName("photo 2026-11-09.png"))
    }

    // T20: Lưu file nhận được vào thư mục Sync của MyNotch
    @Test func fileStorageDestinationPathCreation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = CloudSyncFileStore(baseDirectory: tempDir)
        let transferId = UUID().uuidString
        let testData = Data("Unit test payload content".utf8)

        let targetURL = try store.saveReceivedFile(data: testData, fileName: "document.pdf", transferId: transferId)
        #expect(FileManager.default.fileExists(atPath: targetURL.path))
        let readBack = try Data(contentsOf: targetURL)
        #expect(readBack == testData)
        #expect(targetURL.lastPathComponent == "document.pdf")

        let dirAttrs = try FileManager.default.attributesOfItem(atPath: targetURL.deletingLastPathComponent().path)
        let dirPosix = (dirAttrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        #expect(dirPosix == 0o700)

        let fileAttrs = try FileManager.default.attributesOfItem(atPath: targetURL.path)
        let filePosix = (fileAttrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        #expect(filePosix == 0o600)
    }

    // T25: Chống ghi đè khi nhận cùng tên file nhiều lần
    @Test func nonOverwritingDuplicateFileName() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = CloudSyncFileStore(baseDirectory: tempDir)
        let transferId = UUID().uuidString
        let data1 = Data("First file version".utf8)
        let data2 = Data("Second file version".utf8)

        let url1 = try store.saveReceivedFile(data: data1, fileName: "report.pdf", transferId: transferId)
        let url2 = try store.saveReceivedFile(data: data2, fileName: "report.pdf", transferId: transferId)

        #expect(url1.lastPathComponent == "report.pdf")
        #expect(url2.lastPathComponent == "report (1).pdf")
        #expect(FileManager.default.fileExists(atPath: url1.path))
        #expect(FileManager.default.fileExists(atPath: url2.path))
        #expect(try Data(contentsOf: url1) == data1)
        #expect(try Data(contentsOf: url2) == data2)
    }

    // T26: Kiểm tra ranh giới thư mục và từ chối tiền tố thư mục anh em (sibling prefix vulnerability)
    @Test func siblingDirectoryPrefixContainmentRejected() {
        let base = URL(fileURLWithPath: "/tmp/MyNotch Sync")
        let sibling = URL(fileURLWithPath: "/tmp/MyNotch Sync-other/file.txt")
        let properChild = URL(fileURLWithPath: "/tmp/MyNotch Sync/folder/file.txt")
        #expect(!CloudSyncFileStore.isContained(child: sibling, parent: base))
        #expect(CloudSyncFileStore.isContained(child: properChild, parent: base))
    }

    // T32: Thực nghiệm lưu trữ tệp trên đĩa qua CloudSyncFileStore sản phẩm
    @Test func empiricalEvidenceSaveFile() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ClipboardModuleTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Clipboard
            .deletingLastPathComponent() // Modules
            .deletingLastPathComponent() // Packages
        let evidenceDir = repoRoot.appendingPathComponent("docs/evidence/cloud-sync-v2", isDirectory: true)
        let macSyncDir = evidenceDir.appendingPathComponent("mac_sync_received", isDirectory: true)
        let store = CloudSyncFileStore(baseDirectory: macSyncDir)

        let sourcePath = evidenceDir.appendingPathComponent("empirical_source_test.bin")
        let sourceData: Data
        if FileManager.default.fileExists(atPath: sourcePath.path), let data = try? Data(contentsOf: sourcePath) {
            sourceData = data
        } else {
            sourceData = Data(repeating: 0x42, count: 65536)
        }

        let transferId = "mac-transfer-empirical-001"
        try? FileManager.default.removeItem(at: macSyncDir.appendingPathComponent(transferId))
        let url1 = try store.saveReceivedFile(data: sourceData, fileName: "empirical_test.bin", transferId: transferId)
        let url2 = try store.saveReceivedFile(data: sourceData, fileName: "empirical_test.bin", transferId: transferId)

        #expect(FileManager.default.fileExists(atPath: url1.path))
        #expect(FileManager.default.fileExists(atPath: url2.path))
        #expect(url2.lastPathComponent == "empirical_test (1).bin")
        #expect(try Data(contentsOf: url1) == sourceData)
        #expect(try Data(contentsOf: url2) == sourceData)
    }
}
