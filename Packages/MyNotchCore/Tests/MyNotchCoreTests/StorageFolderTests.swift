import Foundation
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

/// Files and folders under a folder from `ScratchFolders`, so nothing outside the temporary directory is ever touched.
func scratchFolder(_ label: String = "storage") throws -> URL {
    let url = ScratchFolders.shared.reserve(label)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A file of `bytes` bytes whose modification date is `modified` when given.
@discardableResult
func writeFile(_ url: URL, bytes: Int = 10, modified: Date? = nil) throws -> URL {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0x61, count: bytes).write(to: url)
    if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path(percentEncoded: false)) }
    return url
}

/// A sparse file that reports `bytes` bytes without writing them, for tests of megabyte limits that would otherwise fill the disk.
@discardableResult
func writeSparseFile(_ url: URL, bytes: UInt64, modified: Date? = nil) throws -> URL {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    #expect(FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil))
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: bytes)
    try handle.close()
    if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path(percentEncoded: false)) }
    return url
}

func storageItemExists(_ url: URL) -> Bool {
    (try? url.checkResourceIsReachable()) == true || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path(percentEncoded: false))) != nil
}

@Suite struct StorageFolderTests {
    @Test func bytesAddsUpEveryFileInNestedFolders() async throws {
        let folder = try scratchFolder()
        try writeFile(folder.appending(path: "a.bin"), bytes: 100)
        try writeFile(folder.appending(path: "sub/deeper/b.bin"), bytes: 250)
        try writeFile(folder.appending(path: ".hidden"), bytes: 5)
        #expect(await StorageFolder.bytes(in: folder) == 355)
    }

    @Test func bytesOfAFolderThatDoesNotExistIsZero() async {
        #expect(await StorageFolder.bytes(in: ScratchFolders.shared.reserve("missing")) == 0)
    }

    @Test func removeContentsEmptiesTheFolderButKeepsIt() async throws {
        let folder = try scratchFolder()
        try writeFile(folder.appending(path: "a.bin"), bytes: 100)
        try writeFile(folder.appending(path: "sub/b.bin"), bytes: 250)
        try writeFile(folder.appending(path: ".hidden"), bytes: 5)

        #expect(await StorageFolder.removeContents(of: folder) == 355)
        #expect(storageItemExists(folder))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).isEmpty)
    }

    @Test func removeContentsOfAFolderThatDoesNotExistFreesNothingAndCreatesNothing() async {
        let missing = ScratchFolders.shared.reserve("missing")
        #expect(await StorageFolder.removeContents(of: missing) == 0)
        #expect(!storageItemExists(missing))
    }

    @Test func aLinkInsideIsRemovedWithoutTouchingWhatItPointsAt() async throws {
        let outside = try scratchFolder("outside")
        let precious = try writeFile(outside.appending(path: "precious.bin"), bytes: 1_000)
        let folder = try scratchFolder()
        try FileManager.default.createSymbolicLink(at: folder.appending(path: "link-to-file"), withDestinationURL: precious)
        try FileManager.default.createSymbolicLink(at: folder.appending(path: "link-to-folder"), withDestinationURL: outside)

        #expect(await StorageFolder.bytes(in: folder) == 0)
        #expect(await StorageFolder.removeContents(of: folder) == 0)
        #expect(!storageItemExists(folder.appending(path: "link-to-file")))
        #expect(storageItemExists(precious))
        #expect(storageItemExists(outside))
    }

    @Test func aFolderThatIsItselfALinkIsLeftAlone() async throws {
        let outside = try scratchFolder("outside")
        let precious = try writeFile(outside.appending(path: "precious.bin"), bytes: 1_000)
        let link = ScratchFolders.shared.reserve("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        #expect(await StorageFolder.bytes(in: link) == 0)
        #expect(await StorageFolder.removeContents(of: link) == 0)
        #expect(await StorageFolder.files(in: link).isEmpty)
        #expect(storageItemExists(precious))
    }

    @Test func filesReportSizeAndModificationDate() async throws {
        let folder = try scratchFolder()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try writeFile(folder.appending(path: "sub/a.bin"), bytes: 42, modified: date)
        let files = await StorageFolder.files(in: folder)
        #expect(files.count == 1)
        #expect(files.first?.bytes == 42)
        #expect(files.first?.modified == date)
    }

    @Test func removeTakesOnlyTheFilesItIsGivenAndCountsWhatItFreed() async throws {
        let folder = try scratchFolder()
        let doomed = try writeFile(folder.appending(path: "doomed.bin"), bytes: 70)
        let kept = try writeFile(folder.appending(path: "kept.bin"), bytes: 30)
        let files = await StorageFolder.files(in: folder).filter { $0.url.lastPathComponent == "doomed.bin" }

        #expect(await StorageFolder.remove(files) == 70)
        #expect(!storageItemExists(doomed))
        #expect(storageItemExists(kept))
    }
}

@Suite struct CachePolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func file(_ name: String, bytes: Int64 = 10, daysOld: Double) -> StorageFile {
        StorageFile(url: URL(filePath: "/cache/\(name)"), bytes: bytes, modified: now.addingTimeInterval(-daysOld * day))
    }

    private func names(_ files: [StorageFile]) -> [String] { files.map(\.url.lastPathComponent) }

    @Test func theAgeRuleTakesFilesOlderThanTheLimit() {
        let files = [file("old", daysOld: 31), file("edge", daysOld: 30), file("fresh", daysOld: 1)]
        let doomed = CachePolicy.removals(from: files, now: now, maxAge: 30 * day, maxBytes: .max)
        #expect(names(doomed) == ["old"])
    }

    @Test func theSizeRuleTakesTheOldestFirstUntilTheTotalFits() {
        let files = [
            file("newest", bytes: 40, daysOld: 1), file("oldest", bytes: 40, daysOld: 9),
            file("middle", bytes: 40, daysOld: 5),
        ]
        let doomed = CachePolicy.removals(from: files, now: now, maxAge: 30 * day, maxBytes: 100)
        #expect(names(doomed) == ["oldest"])
        let tighter = CachePolicy.removals(from: files, now: now, maxAge: 30 * day, maxBytes: 50)
        #expect(names(tighter) == ["oldest", "middle"])
    }

    @Test func theSizeRuleCountsOnlyWhatTheAgeRuleLeaves() {
        let files = [file("ancient", bytes: 900, daysOld: 90), file("a", bytes: 40, daysOld: 2), file("b", bytes: 40, daysOld: 1)]
        let doomed = CachePolicy.removals(from: files, now: now, maxAge: 30 * day, maxBytes: 100)
        #expect(names(doomed) == ["ancient"])
    }

    @Test func nothingIsTakenWhenBothLimitsHold() {
        let files = [file("a", bytes: 40, daysOld: 2), file("b", bytes: 40, daysOld: 1)]
        #expect(CachePolicy.removals(from: files, now: now, maxAge: 30 * day, maxBytes: 80).isEmpty)
    }

    @Test func filesOfTheSameAgeAreTakenInPathOrder() {
        let files = [file("b", bytes: 40, daysOld: 3), file("a", bytes: 40, daysOld: 3), file("c", bytes: 40, daysOld: 3)]
        let doomed = CachePolicy.removals(from: files, now: now, maxAge: 30 * day, maxBytes: 50)
        #expect(names(doomed) == ["a", "b"])
    }
}
