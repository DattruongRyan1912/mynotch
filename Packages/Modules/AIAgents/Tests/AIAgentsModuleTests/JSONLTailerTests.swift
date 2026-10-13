import Foundation
import Testing
@testable import AIAgentsModule

@Suite final class JSONLTailerTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "JSONLTailerTests-\(UUID().uuidString)")
    let file: URL

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appending(path: "transcript.jsonl")
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func write(_ text: String) throws {
        try Data(text.utf8).write(to: file)
    }

    func append(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    @Test func buffersPartialLinesUntilTheyAreComplete() throws {
        try write("")
        let tailer = JSONLTailer(url: file, startOffset: 0)
        #expect(try tailer.readNewLines() == [])

        try append(#"{"n":1}"# + "\n" + #"{"n":"#)
        #expect(try tailer.readNewLines() == [#"{"n":1}"#])
        #expect(tailer.offset == 8)

        try append("2}")
        #expect(try tailer.readNewLines() == [])
        try append("\n\n" + #"{"n":3}"# + "\r\n")
        #expect(try tailer.readNewLines() == [#"{"n":2}"#, #"{"n":3}"#])
        #expect(try tailer.readNewLines() == [])
        #expect(tailer.offset == UInt64(try Data(contentsOf: file).count))
    }

    @Test func keepsMultibyteCharactersSplitAcrossReads() throws {
        let bytes = Array("{\"t\":\"Bài\"}\n".utf8)
        try Data(bytes[..<8]).write(to: file)
        let tailer = JSONLTailer(url: file, startOffset: 0)
        #expect(try tailer.readNewLines() == [])
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(bytes[8...]))
        try handle.close()
        #expect(try tailer.readNewLines() == ["{\"t\":\"Bài\"}"])
    }

    @Test func restartsFromTheBeginningWhenTheFileIsTruncated() throws {
        try write("a\nb\nc\n")
        let tailer = JSONLTailer(url: file, startOffset: 0)
        #expect(try tailer.readNewLines() == ["a", "b", "c"])

        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("x\n".utf8))
        try handle.close()
        #expect(try tailer.readNewLines() == ["x"])
        #expect(tailer.offset == 2)
    }

    @Test func restartsFromTheBeginningWhenTheFileIsReplaced() throws {
        try write("a\nb\n")
        let tailer = JSONLTailer(url: file, startOffset: 0)
        #expect(try tailer.readNewLines() == ["a", "b"])

        // Longer than before, so only the changed file identity can reveal the replacement.
        try Data("first\nsecond\nthird\n".utf8).write(to: file, options: .atomic)
        #expect(try tailer.readNewLines() == ["first", "second", "third"])
    }

    @Test func startOffsetPastTheEndRestartsFromTheBeginning() throws {
        try write("a\n")
        let tailer = JSONLTailer(url: file, startOffset: 500)
        #expect(try tailer.readNewLines() == ["a"])
    }

    @Test func aNewTailerResumesFromTheSavedOffset() throws {
        try write("one\ntwo\npar")
        let first = JSONLTailer(url: file, startOffset: 0)
        #expect(try first.readNewLines() == ["one", "two"])
        let saved = first.offset
        #expect(saved == 8)

        try append("tial\nthree\n")
        let second = JSONLTailer(url: file, startOffset: saved)
        #expect(try second.readNewLines() == ["partial", "three"])
    }

    @Test func missingFileThrows() {
        let tailer = JSONLTailer(url: directory.appending(path: "missing.jsonl"), startOffset: 0)
        #expect(throws: (any Error).self) { try tailer.readNewLines() }
    }
}
