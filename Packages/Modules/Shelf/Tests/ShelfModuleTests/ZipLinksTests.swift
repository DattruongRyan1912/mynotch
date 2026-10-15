import Foundation
import Testing
@testable import ShelfModule

/// Links go into a zip as links: the system's zip cannot store them, so they are added to its archive afterwards.
@Suite struct ZipLinksTests {
    let folders = OutputFolders(promisedDirectory: nil)
    static let secret = "BÍ MẬT-ngoài-cây-thư-mục"

    func link(_ name: String, to target: String, in folder: URL) throws {
        try FileManager.default.createSymbolicLink(atPath: folder.appending(path: name).path, withDestinationPath: target)
    }

    /// A folder with a file, a link inside it, a link to a file outside, a dangling link, and a subfolder with a link up.
    func makeProject() throws -> (project: URL, outside: URL) {
        let parent = try makeTempDirectory()
        let outside = parent.appending(path: "ngoài.txt")
        try Data(Self.secret.utf8).write(to: outside)
        let project = parent.appending(path: "Dự án", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project.appending(path: "con"), withIntermediateDirectories: true)
        _ = try makeTempFile(named: "a.txt", in: project)
        _ = try makeTempFile(named: "b.txt", in: project.appending(path: "con"))
        try link("trong", to: "a.txt", in: project)
        try link("ngoài", to: outside.path, in: project)
        try link("treo", to: "không-có.txt", in: project)
        try link("lên", to: "../a.txt", in: project.appending(path: "con"))
        return (project, outside)
    }

    func records(_ zip: URL) throws -> [String: SyntheticFiles.ZipRecord] {
        Dictionary(uniqueKeysWithValues: try SyntheticFiles.zipRecords(zip).map { ($0.name.precomposedStringWithCanonicalMapping, $0) })
    }

    // MARK: Zipping

    @Test func aFolderWithLinksKeepsEveryLinkAsALinkAndFollowsNone() throws {
        let (project, outside) = try makeProject()
        let made = try ZipArchive.make(from: [project], folders: folders)
        #expect(made.unstoredLinks.isEmpty)
        let records = try records(made.file)
        for (name, target) in [("trong", "a.txt"), ("ngoài", outside.path), ("treo", "không-có.txt"), ("con/lên", "../a.txt")] {
            let record = try #require(records["Dự án/\(name)"], "\(name)")
            #expect(record.isLink && record.stored.map { String(decoding: $0, as: UTF8.self) } == target)
        }
        #expect(records["Dự án/a.txt"]?.isLink == false && records["Dự án/con/b.txt"]?.isLink == false)
        // What a link points at outside the folder is not in the archive.
        #expect(try !Data(contentsOf: made.file).contains(Data(Self.secret.utf8)))
        // The folder itself is as it was.
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: project.appending(path: "ngoài").path) == outside.path)
    }

    @Test func theArchiveUnpacksWithItsLinksAsLinks() throws {
        let (project, outside) = try makeProject()
        let made = try ZipArchive.make(from: [project], folders: folders)
        let unpacked = try makeTempDirectory()
        // The system's own unarchiver, as Finder would use, checks the archive is well formed.
        let tool = Process()
        tool.executableURL = URL(filePath: "/usr/bin/ditto")
        tool.arguments = ["-x", "-k", made.file.path, unpacked.path]
        try tool.run()
        tool.waitUntilExit()
        #expect(tool.terminationStatus == 0)
        let root = unpacked.appending(path: "Dự án")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: root.appending(path: "trong").path) == "a.txt")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: root.appending(path: "ngoài").path) == outside.path)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: root.appending(path: "treo").path) == "không-có.txt")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: root.appending(path: "con/lên").path) == "../a.txt")
        #expect(try String(contentsOf: root.appending(path: "a.txt"), encoding: .utf8) == "hello")
        #expect(try String(contentsOf: root.appending(path: "con/b.txt"), encoding: .utf8) == "hello")
    }

    @Test func aLinkDroppedAloneIsZippedAsTheLink() throws {
        let (_, outside) = try makeProject()
        let folder = outside.deletingLastPathComponent()
        try link("đường dẫn", to: outside.path, in: folder)
        let made = try ZipArchive.make(from: [folder.appending(path: "đường dẫn")], folders: folders)
        #expect(made.file.lastPathComponent == "đường dẫn.zip")
        let records = try records(made.file)
        let record = try #require(records["đường dẫn/đường dẫn"])
        #expect(record.isLink && record.stored.map { String(decoding: $0, as: UTF8.self) } == outside.path)
        #expect(try !Data(contentsOf: made.file).contains(Data(Self.secret.utf8)))
    }

    @Test func aLinkToAFolderDroppedAloneIsNotFollowed() throws {
        let (project, _) = try makeProject()
        let folder = project.deletingLastPathComponent()
        try link("lối tắt", to: project.path, in: folder)
        let made = try ZipArchive.make(from: [folder.appending(path: "lối tắt")], folders: folders)
        let records = try records(made.file)
        #expect(records["lối tắt/lối tắt"]?.isLink == true)
        #expect(records.keys.allSatisfy { !$0.contains("a.txt") && !$0.contains("b.txt") })
    }

    @Test func aDanglingLinkDroppedAloneCanBeZippedToo() throws {
        let folder = try makeTempDirectory()
        try link("treo", to: "không-có", in: folder)
        let made = try ZipArchive.make(from: [folder.appending(path: "treo")], folders: folders)
        #expect(try records(made.file)["treo/treo"]?.isLink == true)
    }

    @Test func severalSourcesIncludingALinkKeepTheLink() throws {
        let (project, _) = try makeProject()
        let folder = project.deletingLastPathComponent()
        try link("lối tắt", to: "a.txt", in: folder)
        let file = try makeTempFile(named: "a.txt", in: folder)
        let made = try ZipArchive.make(from: [file, folder.appending(path: "lối tắt"), project], folders: folders)
        let records = try records(made.file)
        #expect(records["Lưu trữ/lối tắt"]?.isLink == true)
        #expect(records["Lưu trữ/Dự án/trong"]?.isLink == true)
        #expect(records["Lưu trữ/a.txt"]?.isLink == false)
    }

    @Test func aFolderWithoutLinksIsStillZippedWhereItIs() throws {
        let folder = try makeTempDirectory(), staging = try makeTempDirectory()
        let source = folder.appending(path: "Thường", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        _ = try makeTempFile(named: "a.txt", in: source)
        var steps: [ZipStep] = []
        _ = try ZipArchive.make(from: [source], folders: folders, stagingRoot: staging) { steps.append($0) }
        // Nothing was copied: a big folder is not duplicated just to be zipped.
        #expect(steps == [.zipped, .placed])
    }

    @Test func linksThatCannotBeStoredAreReportedAndTheRestIsStillZipped() throws {
        let (project, _) = try makeProject()
        let made = try ZipArchive.make(from: [project], folders: folders, storeLinks: { _, _ in throw ZipLinks.Failure.unsupported })
        #expect(Set(made.unstoredLinks.map(\.lastPathComponent)) == ["trong", "ngoài", "treo", "lên"])
        let records = try records(made.file)
        #expect(records["Dự án/a.txt"] != nil && records["Dự án/con/b.txt"] != nil)
        #expect(records["Dự án/trong"] == nil)
    }

    @Test func aFailureWhileWritingTheLinksLeavesNoZip() throws {
        let (project, _) = try makeProject()
        let parent = project.deletingLastPathComponent()
        let before = try FileManager.default.contentsOfDirectory(atPath: parent.path).sorted()
        #expect(throws: FileActionError.cannotWrite) {
            try ZipArchive.make(from: [project], folders: folders, storeLinks: { _, _ in throw FileActionError.cannotWrite })
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path).sorted() == before)
    }

    // MARK: Adding links to an archive

    func systemZip() throws -> URL {
        let folder = try makeTempDirectory()
        let file = try makeTempFile(named: "a.txt", in: folder)
        return try ZipArchive.make(from: [file], folders: folders).file
    }

    @Test func appendingKeepsTheEntriesThatWereThere() throws {
        let zip = try systemZip()
        let before = try records(zip)
        try ZipLinks.append([ZipLink(path: "a/liên kết", target: "a.txt", source: zip)], to: zip)
        let after = try records(zip)
        #expect(Set(after.keys) == Set(before.keys).union(["a/liên kết"]))
        #expect(after["a/liên kết"]?.isLink == true)
        #expect(after["a/a.txt"]?.mode == before["a/a.txt"]?.mode)
    }

    @Test func anArchiveThatIsNotOneIsLeftAsItWas() throws {
        let folder = try makeTempDirectory()
        let file = try makeTempFile(in: folder)
        let before = try Data(contentsOf: file)
        #expect(throws: ZipLinks.Failure.unsupported) { try ZipLinks.append([ZipLink(path: "x", target: "y", source: file)], to: file) }
        #expect(try Data(contentsOf: file) == before)
    }

    @Test func anArchiveThatNeedsZip64IsLeftAsItWas() throws {
        let folder = try makeTempDirectory()
        // An end record whose offset and size are the "see zip64" values.
        var record = Data([0x50, 0x4B, 0x05, 0x06, 0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF])
        record.append(Data(repeating: 0xFF, count: 8))
        record.append(Data([0, 0]))
        let zip = folder.appending(path: "big.zip")
        try record.write(to: zip)
        #expect(throws: ZipLinks.Failure.unsupported) { try ZipLinks.append([ZipLink(path: "x", target: "y", source: zip)], to: zip) }
        #expect(try Data(contentsOf: zip) == record)
    }

    @Test func theChecksumIsTheStandardOne() {
        #expect(CRC32.checksum(Array("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum([]) == 0)
    }
}
