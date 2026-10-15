import Foundation
import Testing
@testable import ShelfModule

@Suite struct ResultsFolderTests {
    func setUp() throws -> (promised: URL, results: URL, folders: OutputFolders) {
        let root = try makeTempDirectory()
        let promised = root.appending(path: "promised", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: promised, withIntermediateDirectories: true)
        return (promised, root.appending(path: "Kết quả", directoryHint: .isDirectory), OutputFolders(promisedDirectory: promised))
    }

    /// A result in a promised folder of its own, as an action leaves it.
    func promisedResult(_ name: String, in promised: URL) throws -> URL {
        let folder = promised.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try makeTempFile(named: name, in: folder)
    }

    func result(_ url: URL, _ reason: UnshelvedResult.Reason = .shelfFull) -> UnshelvedResult { UnshelvedResult(url: url, reason: reason) }

    @Test func aResultInPromisedStorageMovesOutAndItsFolderGoes() throws {
        let (promised, results, folders) = try setUp()
        let file = try promisedResult("ảnh-800.png", in: promised)
        let moved = ResultsFolder.rescue([result(file)], folders: folders, into: results)
        let url = try #require(moved.first?.url)
        #expect(url.deletingLastPathComponent().resolvingSymlinksInPath() == results.resolvingSymlinksInPath())
        #expect(url.lastPathComponent == "ảnh-800.png" && exists(url) && !exists(file))
        #expect(moved.first?.reason == .shelfFull)
        #expect(try FileManager.default.contentsOfDirectory(atPath: promised.path).isEmpty)
    }

    @Test func nothingIsReplacedInTheResultsFolder() throws {
        let (promised, results, folders) = try setUp()
        let one = try promisedResult("a.png", in: promised), two = try promisedResult("a.png", in: promised)
        let moved = ResultsFolder.rescue([result(one), result(two)], folders: folders, into: results)
        #expect(moved.map(\.url.lastPathComponent) == ["a.png", "a 2.png"])
        #expect(moved.allSatisfy { exists($0.url) })
    }

    @Test func aResultThatHasAFolderOfItsOwnIsLeftWhereItIs() throws {
        let (_, results, folders) = try setUp()
        let beside = try makeTempFile(named: "a.png", in: try makeTempDirectory())
        let moved = ResultsFolder.rescue([result(beside, .cardFailed)], folders: folders, into: results)
        #expect(moved == [result(beside, .cardFailed)])
        #expect(exists(beside) && !exists(results))
    }

    @Test func aResultThatCannotBeMovedStaysAndIsMarkedAsStranded() throws {
        let (promised, _, folders) = try setUp()
        let file = try promisedResult("a.png", in: promised)
        let blocker = try makeTempFile(in: try makeTempDirectory())
        let moved = ResultsFolder.rescue([result(file)], folders: folders, into: blocker.appending(path: "MyNotch"))
        #expect(moved == [result(file, .stranded)])
        #expect(exists(file))
    }

    @Test func theStandardFolderIsMyNotchInDownloads() {
        #expect(ResultsFolder.standard.lastPathComponent == "MyNotch")
        #expect(ResultsFolder.standard.deletingLastPathComponent().lastPathComponent == "Downloads")
    }

    @Test func promisedStorageIsRecognisedFromTheFolderOfAFile() throws {
        let (promised, _, folders) = try setUp()
        #expect(folders.holdsPromised(try promisedResult("a.png", in: promised)))
        #expect(!folders.holdsPromised(try makeTempFile(in: try makeTempDirectory())))
        #expect(!OutputFolders(promisedDirectory: nil).holdsPromised(promised.appending(path: "x/a.png")))
    }
}
