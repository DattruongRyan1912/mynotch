import Foundation
import Testing
@testable import MediaModule

@Suite struct LineBufferTests {
    @Test func joinsPartialChunksIntoCompleteLines() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data(#"{"n":1}"#.utf8)) == [])
        #expect(buffer.append(Data("\n{\"n\":".utf8)) == [#"{"n":1}"#])
        #expect(buffer.append(Data("2}\n{\"n\":3}\n".utf8)) == [#"{"n":2}"#, #"{"n":3}"#])
        #expect(buffer.finish() == [])
    }

    @Test func keepsMultibyteCharactersSplitAcrossChunks() {
        let bytes = Array("Bài hát\n".utf8)
        var buffer = LineBuffer()
        #expect(buffer.append(Data(bytes[..<2])) == [])
        #expect(buffer.append(Data(bytes[2...])) == ["Bài hát"])
    }

    @Test func skipsEmptyLinesAndFlushesTheUnterminatedRest() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("\n\na\n\nb".utf8)) == ["a"])
        #expect(buffer.finish() == ["b"])
        #expect(buffer.finish() == [])
    }
}
