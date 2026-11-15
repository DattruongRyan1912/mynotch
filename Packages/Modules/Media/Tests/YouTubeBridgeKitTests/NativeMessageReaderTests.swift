import Foundation
import Testing
@testable import YouTubeBridgeKit

@Suite struct NativeMessageReaderTests {
    @Test func readsAMessageWithANativeEndianLength() {
        var reader = NativeMessageReader(source: ScriptedReader(nativeFrame("{\"a\":1}")))
        #expect(reader.next() == .message(Data("{\"a\":1}".utf8)))
        #expect(reader.next() == .end)
    }

    @Test func theLengthIsInTheMachinesByteOrder() {
        let message = Data("hello".utf8)
        let header = withUnsafeBytes(of: UInt32(5)) { Data($0) }
        #expect(header == Data(withUnsafeBytes(of: UInt32(5).littleEndian) { $0 }), "this test assumes a little-endian machine")
        var reader = NativeMessageReader(source: ScriptedReader(header + message))
        #expect(reader.next() == .message(message))
    }

    @Test func messagesOneByteAtATimeComeOutWhole() {
        let stream = nativeFrame("first") + nativeFrame("second one") + nativeFrame("3")
        var reader = NativeMessageReader(source: ScriptedReader(stream, piece: 1))
        #expect(reader.next() == .message(Data("first".utf8)))
        #expect(reader.next() == .message(Data("second one".utf8)))
        #expect(reader.next() == .message(Data("3".utf8)))
        #expect(reader.next() == .end)
    }

    @Test func severalMessagesInOneReadAreSeparated() {
        var reader = NativeMessageReader(source: ScriptedReader(nativeFrame("a") + nativeFrame("bb")))
        #expect(reader.next() == .message(Data("a".utf8)))
        #expect(reader.next() == .message(Data("bb".utf8)))
    }

    @Test func anEmptyMessageIsAMessage() {
        var reader = NativeMessageReader(source: ScriptedReader(nativeFrame(Data())))
        #expect(reader.next() == .message(Data()))
    }

    @Test func endOfInputInsideAHeaderOrABodyEndsTheStream() {
        let whole = nativeFrame("complete message")
        for cut in [0, 1, 3, 4, 5, whole.count - 1] {
            var reader = NativeMessageReader(source: ScriptedReader(whole.prefix(cut)))
            #expect(reader.next() == .end, "cut at \(cut)")
        }
    }

    @Test func aLengthAboveSixtyFourMebibytesIsRefusedWithoutReadingTheBody() {
        let header = withUnsafeBytes(of: UInt32(NativeMessageReader<ScriptedReader>.maxLength + 1)) { Data($0) }
        let source = ScriptedReader(header + Data("x".utf8))
        var reader = NativeMessageReader(source: source)
        #expect(reader.next() == .tooLarge(NativeMessageReader<ScriptedReader>.maxLength + 1))
        #expect(source.reads == 1)
    }

    @Test func aMessageOfExactlySixtyFourMebibytesIsAllowed() {
        let body = Data(repeating: 0x20, count: NativeMessageReader<ScriptedReader>.maxLength)
        var reader = NativeMessageReader(source: ScriptedReader(nativeFrame(body), piece: 1 << 20))
        #expect(reader.next() == .message(body))
    }

    @Test func aFileDescriptorReaderReadsAPipeUntilItIsClosed() throws {
        var fds: [Int32] = [0, 0]
        #expect(pipe(&fds) == 0)
        let frame = nativeFrame("through a pipe")
        frame.withUnsafeBytes { _ = write(fds[1], $0.baseAddress, $0.count) }
        close(fds[1])
        defer { close(fds[0]) }
        var reader = NativeMessageReader(source: FileDescriptorReader(fileDescriptor: fds[0]))
        #expect(reader.next() == .message(Data("through a pipe".utf8)))
        #expect(reader.next() == .end)
    }
}
