import Foundation
import Testing
@testable import ShelfModule

@Suite struct ZipArchiveTests {
    let folders = OutputFolders(promisedDirectory: nil)

    func entries(_ url: URL) throws -> [String] {
        try SyntheticFiles.zipEntries(url).map(\.precomposedStringWithCanonicalMapping).sorted()
    }

    func files(_ url: URL) throws -> [String] {
        try entries(url).filter { !$0.hasSuffix("/") }
    }

    func isEmpty(_ folder: URL) throws -> Bool {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty
    }

    @Test func aSingleFileIsZippedUnderItsOwnName() throws {
        let folder = try makeTempDirectory()
        let file = try makeTempFile(named: "báo cáo.txt", in: folder)
        let made = try ZipArchive.make(from: [file], folders: folders)
        #expect(made.file.deletingLastPathComponent() == folder)
        #expect(made.file.lastPathComponent == "báo cáo.zip")
        #expect(try entries(made.file) == ["báo cáo/báo cáo.txt"])
        #expect(made.unstoredLinks.isEmpty)
        #expect(exists(file))
    }

    @Test func aFolderKeepsItsStructure() throws {
        let folder = try makeTempDirectory()
        let source = folder.appending(path: "Ảnh", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source.appending(path: "con"), withIntermediateDirectories: true)
        _ = try makeTempFile(named: "a.txt", in: source)
        _ = try makeTempFile(named: "b.txt", in: source.appending(path: "con"))
        let made = try ZipArchive.make(from: [source], folders: folders)
        #expect(made.file.lastPathComponent == "Ảnh.zip")
        #expect(try files(made.file) == ["Ảnh/a.txt", "Ảnh/con/b.txt"])
    }

    @Test func severalSourcesMakeOneZipNextToTheFirst() throws {
        let one = try makeTempDirectory(), two = try makeTempDirectory()
        let a = try makeTempFile(named: "a.txt", in: one)
        let b = try makeTempFile(named: "a.txt", in: two)
        let made = try ZipArchive.make(from: [a, b], folders: folders)
        #expect(made.file.deletingLastPathComponent() == one)
        #expect(made.file.lastPathComponent == "Lưu trữ.zip")
        #expect(try files(made.file) == ["Lưu trữ/a 2.txt", "Lưu trữ/a.txt"])
    }

    @Test func severalSourcesKeepTheFoldersTheyHold() throws {
        let folder = try makeTempDirectory()
        let source = folder.appending(path: "Thư mục", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        _ = try makeTempFile(named: "b.txt", in: source)
        let a = try makeTempFile(named: "a.txt", in: folder)
        let made = try ZipArchive.make(from: [a, source], folders: folders)
        #expect(try files(made.file) == ["Lưu trữ/Thư mục/b.txt", "Lưu trữ/a.txt"].sorted())
    }

    @Test func neverReplacesAZipThatIsThere() throws {
        let folder = try makeTempDirectory()
        let file = try makeTempFile(named: "a.txt", in: folder)
        let first = try ZipArchive.make(from: [file], folders: folders).file
        let second = try ZipArchive.make(from: [file], folders: folders).file
        #expect(first.lastPathComponent == "a.zip" && second.lastPathComponent == "a 2.zip")
        #expect(exists(first) && exists(second))
    }

    @Test func aMissingSourceIsAnError() throws {
        let folder = try makeTempDirectory()
        #expect(throws: FileActionError.missing) { try ZipArchive.make(from: [folder.appending(path: "gone.txt")], folders: folders) }
        #expect(try isEmpty(folder))
    }

    // MARK: Staging

    @Test func leavesNoStagingFolderBehind() throws {
        let folder = try makeTempDirectory(), staging = try makeTempDirectory()
        let file = try makeTempFile(in: folder)
        _ = try ZipArchive.make(from: [file], folders: folders, stagingRoot: staging)
        #expect(try isEmpty(staging))
    }

    @Test func aFailedZipLeavesNoStagingFolderEither() throws {
        let folder = try makeTempDirectory(), staging = try makeTempDirectory()
        let file = try makeTempFile(in: folder)
        let missing = folder.appending(path: "gone.txt")
        #expect(throws: FileActionError.missing) { try ZipArchive.make(from: [file, missing], folders: folders, stagingRoot: staging) }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        #expect(throws: FileActionError.cannotWrite) { try ZipArchive.make(from: [file], folders: folders, stagingRoot: staging) }
        #expect(try isEmpty(staging))
    }

    @Test func aReadOnlyFolderInTheSourceDoesNotKeepTheStagingCopyAlive() throws {
        let folder = try makeTempDirectory(), staging = try makeTempDirectory()
        let source = folder.appending(path: "RO", directoryHint: .isDirectory)
        let locked = source.appending(path: "ro", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        _ = try makeTempFile(named: "a.txt", in: locked)
        // A link makes the folder take the staged route, which copies it.
        try FileManager.default.createSymbolicLink(atPath: source.appending(path: "lk").path, withDestinationPath: "ro/a.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let made = try ZipArchive.make(from: [source], folders: folders, stagingRoot: staging)
        #expect(try files(made.file).contains("RO/ro/a.txt"))
        #expect(try isEmpty(staging))
    }

    // MARK: Cancelling

    @Test func aTaskCancelledBeforeItStartsWritesNothing() async throws {
        let folder = try makeTempDirectory(), staging = try makeTempDirectory()
        let file = try makeTempFile(in: folder)
        let task = Task.detached { [folders] in
            withUnsafeCurrentTask { $0?.cancel() }
            return Result { try ZipArchive.make(from: [file], folders: folders, stagingRoot: staging) }
        }
        let result = await task.value
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["note.txt"])
        #expect(try isEmpty(staging))
    }

    @Test func cancellingWhileFilesAreBeingStagedStopsBeforeTheNextOne() async throws {
        let folder = try makeTempDirectory(), staging = try makeTempDirectory()
        let sources = try ["a.txt", "b.txt", "c.txt"].map { try makeTempFile(named: $0, in: folder) }
        let task = Task.detached { [folders] in
            Result {
                try ZipArchive.make(from: sources, folders: folders, stagingRoot: staging) { step in
                    // The user cancels once the first file is copied.
                    if step == .staged(1) { withUnsafeCurrentTask { $0?.cancel() } }
                }
            }
        }
        let result = await task.value
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)) == ["a.txt", "b.txt", "c.txt"])
        #expect(try isEmpty(staging))
    }

    @Test func aCancelPressedDuringTheLastCopyRemovesTheZipAndReportsCancelled() async throws {
        let folder = try makeTempDirectory(), staging = try makeTempDirectory()
        let file = try makeTempFile(in: folder)
        let task = Task.detached { [folders] in
            Result {
                try ZipArchive.make(from: [file], folders: folders, stagingRoot: staging) { step in
                    // The zip has just been copied into place when the user cancels.
                    if step == .placed { withUnsafeCurrentTask { $0?.cancel() } }
                }
            }
        }
        let result = await task.value
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["note.txt"])
        #expect(try isEmpty(staging))
    }

    @Test func cancellingWhileTheSystemZipsDeliversNothing() async throws {
        let folder = try makeTempDirectory(), staging = try makeTempDirectory()
        let file = try makeTempFile(in: folder)
        let task = Task.detached { [folders] in
            Result {
                try ZipArchive.make(from: [file], folders: folders, stagingRoot: staging) { step in
                    // The system's zip step cannot be interrupted, so the cancel arrives once it is done.
                    if step == .zipped { withUnsafeCurrentTask { $0?.cancel() } }
                }
            }
        }
        let result = await task.value
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["note.txt"])
        #expect(try isEmpty(staging))
    }
}
