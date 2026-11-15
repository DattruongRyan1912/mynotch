import Foundation
import Testing
@testable import CleanerModule

@Suite("SystemCleanScanner Tests")
struct SystemCleanScannerTests {
    @Test("Quét trả về các danh mục chuẩn của Catalog")
    func testCatalogScanning() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Setup mock DerivedData with a child project folder
        let derivedData = tempDir.appending(path: "Library/Developer/Xcode/DerivedData")
        let projectDir = derivedData.appending(path: "MyApp-xyz")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let sampleFile = projectDir.appending(path: "sample.txt")
        try "sample content".write(to: sampleFile, atomically: true, encoding: .utf8)

        let result = await SystemCleanScanner.scan(
            home: tempDir,
            runningIDs: [],
            runningNames: []
        )

        #expect(!result.categories.isEmpty)
        if let xcodeCat = result.categories.first(where: { $0.id == "cleaner.dev.deriveddata" }) {
            #expect(xcodeCat.bytes > 0)
            #expect(xcodeCat.scope == .developer)
        }
    }

    @Test("Tạo DeletionPlan hợp lệ cho danh mục đã quét")
    func testPlanCreation() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let npmCache = tempDir.appending(path: ".npm/_cacache")
        try FileManager.default.createDirectory(at: npmCache, withIntermediateDirectories: true)
        let dummy = npmCache.appending(path: "dummy.bin")
        try "npm binary cache".write(to: dummy, atomically: true, encoding: .utf8)

        let result = await SystemCleanScanner.scan(
            home: tempDir,
            runningIDs: [],
            runningNames: []
        )

        let npmPlan = result.plans["cleaner.dev.npm"]
        #expect(npmPlan != nil)
        #expect(npmPlan?.items.isEmpty == false)
    }
}
