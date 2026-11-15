import Foundation
import Testing
@testable import ShelfModule

@Suite struct OutputNamingTests {
    @Test func theSuffixGoesBetweenTheNameAndTheExtension() {
        #expect(OutputNaming.fileName(stem: "ảnh", suffix: "1280", ext: "jpg") == "ảnh-1280.jpg")
        #expect(OutputNaming.fileName(stem: "ảnh", suffix: "không-nền", ext: "png") == "ảnh-không-nền.png")
        #expect(OutputNaming.fileName(stem: "ảnh", suffix: nil, ext: "pdf") == "ảnh.pdf")
    }

    @Test func theNameIsPrecomposedSoDecomposedAndTypedLettersDoNotMix() {
        let decomposed = "a\u{0309}nh"
        let name = OutputNaming.fileName(stem: decomposed, suffix: "không-nền", ext: "png")
        #expect(name.unicodeScalars.elementsEqual(name.precomposedStringWithCanonicalMapping.unicodeScalars))
    }

    @Test func writesNextToTheSourceUnderTheFirstFreeName() throws {
        let folder = try makeTempDirectory()
        let first = try OutputNaming.place(stem: "ảnh", suffix: "800", ext: "jpg", in: folder) { try Data("1".utf8).write(to: $0, options: .withoutOverwriting) }
        let second = try OutputNaming.place(stem: "ảnh", suffix: "800", ext: "jpg", in: folder) { try Data("2".utf8).write(to: $0, options: .withoutOverwriting) }
        let third = try OutputNaming.place(stem: "ảnh", suffix: "800", ext: "jpg", in: folder) { try Data("3".utf8).write(to: $0, options: .withoutOverwriting) }
        #expect([first, second, third].map(\.lastPathComponent) == ["ảnh-800.jpg", "ảnh-800 2.jpg", "ảnh-800 3.jpg"])
        #expect(try String(contentsOf: first, encoding: .utf8) == "1")
        #expect(try String(contentsOf: second, encoding: .utf8) == "2")
    }

    @Test func aFileThatAppearsAfterTheCheckIsNotOverwritten() throws {
        let folder = try makeTempDirectory()
        var attempts = 0
        let url = try OutputNaming.place(stem: "a", suffix: nil, ext: "png", in: folder) { candidate in
            attempts += 1
            // Another process takes the name between the check and the write.
            if attempts == 1 { try Data("other".utf8).write(to: candidate) }
            try Data("mine".utf8).write(to: candidate, options: .withoutOverwriting)
        }
        #expect(url.lastPathComponent == "a 2.png")
        #expect(try String(contentsOf: folder.appending(path: "a.png"), encoding: .utf8) == "other")
    }

    @Test func aWriteThatFailsLeavesNothingBehindAndReportsCannotWrite() throws {
        let folder = try makeTempDirectory()
        #expect(throws: FileActionError.cannotWrite) {
            try OutputNaming.place(stem: "a", suffix: nil, ext: "png", in: folder) { candidate in
                try Data("half".utf8).write(to: candidate)
                throw CocoaError(.fileWriteOutOfSpace)
            }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func createsTheFolderWhenItIsNotThereYet() throws {
        let folder = try makeTempDirectory().appending(path: "new/inner", directoryHint: .isDirectory)
        let url = try OutputNaming.place(stem: "a", suffix: nil, ext: "png", in: folder) { try Data("x".utf8).write(to: $0, options: .withoutOverwriting) }
        #expect(exists(url))
    }

    @Test func aPercentSignInTheSuffixSurvivesInTheFileName() throws {
        let folder = try makeTempDirectory()
        let url = try OutputNaming.place(stem: "ảnh", suffix: "50%", ext: "png", in: folder) { try Data("x".utf8).write(to: $0, options: .withoutOverwriting) }
        #expect(url.lastPathComponent == "ảnh-50%.png")
        #expect(exists(url))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["ảnh-50%.png"])
    }

    @Test func aSourceInTheShelfsPromisedFolderGetsAFolderOfItsOwn() throws {
        let promised = try makeTempDirectory().appending(path: "promised", directoryHint: .isDirectory)
        let folders = OutputFolders(promisedDirectory: promised)
        let ownFolder = promised.appending(path: "ABC", directoryHint: .isDirectory)
        let source = ownFolder.appending(path: "photo.heic")
        let first = folders.folder(for: source), second = folders.folder(for: source)
        #expect(first != ownFolder && second != ownFolder && first != second)
        #expect(first.deletingLastPathComponent().resolvingSymlinksInPath() == promised.resolvingSymlinksInPath())
    }

    @Test func aSourceAnywhereElseKeepsItsOwnFolder() throws {
        let promised = try makeTempDirectory().appending(path: "promised", directoryHint: .isDirectory)
        let folder = try makeTempDirectory()
        let source = folder.appending(path: "photo.heic")
        #expect(OutputFolders(promisedDirectory: promised).folder(for: source) == folder)
        #expect(OutputFolders(promisedDirectory: nil).folder(for: source) == folder)
    }
}
