import Foundation
import Testing
@testable import ShelfModule

@Suite struct ZipArchiveTests {
    func entries(_ url: URL) throws -> [String] {
        try SyntheticFiles.zipEntries(url).map(\.precomposedStringWithCanonicalMapping).sorted()
    }

    @Test func aSingleFileIsZippedUnderItsOwnName() throws {
        let folder = try makeTempDirectory()
        let file = try makeTempFile(named: "báo cáo.txt", in: folder)
        let zip = try ZipArchive.make(from: [file], folders: OutputFolders(promisedDirectory: nil))
        #expect(zip.deletingLastPathComponent() == folder)
        #expect(zip.lastPathComponent == "báo cáo.zip")
        #expect(try entries(zip) == ["báo cáo/báo cáo.txt"])
        #expect(exists(file))
    }

    @Test func aFolderKeepsItsStructure() throws {
        let folder = try makeTempDirectory()
        let source = folder.appending(path: "Ảnh", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source.appending(path: "con"), withIntermediateDirectories: true)
        _ = try makeTempFile(named: "a.txt", in: source)
        _ = try makeTempFile(named: "b.txt", in: source.appending(path: "con"))
        let zip = try ZipArchive.make(from: [source], folders: OutputFolders(promisedDirectory: nil))
        #expect(zip.lastPathComponent == "Ảnh.zip")
        #expect(try entries(zip).filter { !$0.hasSuffix("/") } == ["Ảnh/a.txt", "Ảnh/con/b.txt"])
    }

    @Test func severalSourcesMakeOneZipNextToTheFirst() throws {
        let one = try makeTempDirectory(), two = try makeTempDirectory()
        let a = try makeTempFile(named: "a.txt", in: one)
        let b = try makeTempFile(named: "a.txt", in: two)
        let zip = try ZipArchive.make(from: [a, b], folders: OutputFolders(promisedDirectory: nil))
        #expect(zip.deletingLastPathComponent() == one)
        #expect(zip.lastPathComponent == "Lưu trữ.zip")
        #expect(try entries(zip).filter { !$0.hasSuffix("/") } == ["Lưu trữ/a 2.txt", "Lưu trữ/a.txt"])
    }

    @Test func neverReplacesAZipThatIsThere() throws {
        let folder = try makeTempDirectory()
        let file = try makeTempFile(named: "a.txt", in: folder)
        let first = try ZipArchive.make(from: [file], folders: OutputFolders(promisedDirectory: nil))
        let second = try ZipArchive.make(from: [file], folders: OutputFolders(promisedDirectory: nil))
        #expect(first.lastPathComponent == "a.zip" && second.lastPathComponent == "a 2.zip")
        #expect(exists(first) && exists(second))
    }

    @Test func aMissingSourceIsAnError() throws {
        let folder = try makeTempDirectory()
        #expect(throws: FileActionError.missing) {
            try ZipArchive.make(from: [folder.appending(path: "gone.txt")], folders: OutputFolders(promisedDirectory: nil))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func leavesNoStagingFolderBehind() throws {
        let folder = try makeTempDirectory()
        let file = try makeTempFile(in: folder)
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory())) ?? []).filter { $0.hasPrefix("MyNotch-zip-") }
        _ = try ZipArchive.make(from: [file], folders: OutputFolders(promisedDirectory: nil))
        let after = Set((try? FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory())) ?? []).filter { $0.hasPrefix("MyNotch-zip-") }
        #expect(after == before)
    }

    @Test func aCancelledZipWritesNothing() async throws {
        let folder = try makeTempDirectory()
        let file = try makeTempFile(in: folder)
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return Result { try ZipArchive.make(from: [file], folders: OutputFolders(promisedDirectory: nil)) }
        }
        let result = await task.value
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["note.txt"])
    }
}
