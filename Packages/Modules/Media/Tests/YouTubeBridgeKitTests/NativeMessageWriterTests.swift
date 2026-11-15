import Foundation
import Testing
@testable import YouTubeBridgeKit

@Suite struct NativeMessageWriterTests {
    @Test func aNativeMessageIsTheLengthInTheMachinesByteOrderThenThePayload() {
        let frame = NativeMessage.frame(Data("abc".utf8))
        #expect(frame == withUnsafeBytes(of: UInt32(3)) { Data($0) } + Data("abc".utf8))
        #expect(frame.count == 7)
    }

    @Test func whatTheWriterWritesTheReaderReadsBack() throws {
        var fds: [Int32] = [0, 0]
        #expect(pipe(&fds) == 0)
        defer { close(fds[0]) }
        let writer = FileDescriptorWriter(fileDescriptor: fds[1])
        let first = NativeMessage.frame(YouTubeCommand.next.json)
        let second = NativeMessage.frame(YouTubeCommand.previous.json)
        #expect(writer.write(first))
        #expect(writer.write(second))
        close(fds[1])
        var reader = NativeMessageReader(source: FileDescriptorReader(fileDescriptor: fds[0]))
        #expect(reader.next() == .message(YouTubeCommand.next.json))
        #expect(reader.next() == .message(YouTubeCommand.previous.json))
        #expect(reader.next() == .end)
    }

    @Test func aPipeThatWasClosedFailsTheWriteInsteadOfEndingTheProcess() {
        var fds: [Int32] = [0, 0]
        #expect(pipe(&fds) == 0)
        close(fds[0])
        defer { close(fds[1]) }
        // Without F_SETNOSIGPIPE this write would raise SIGPIPE and the test process would die.
        let writer = FileDescriptorWriter(fileDescriptor: fds[1])
        #expect(!writer.write(NativeMessage.frame(YouTubeCommand.next.json)))
    }

    @Test func writersOnSeveralThreadsNeverInterleaveTheirMessages() async throws {
        var fds: [Int32] = [0, 0]
        #expect(pipe(&fds) == 0)
        let writer = FileDescriptorWriter(fileDescriptor: fds[1])
        let commands = YouTubeCommand.allCases
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask { _ = writer.write(NativeMessage.frame(commands[index % 2].json)) }
            }
        }
        close(fds[1])
        defer { close(fds[0]) }
        var reader = NativeMessageReader(source: FileDescriptorReader(fileDescriptor: fds[0]))
        var count = 0
        while case .message(let message) = reader.next() {
            #expect(YouTubeCommand.decode(message) != nil)
            count += 1
        }
        #expect(count == 40)
    }
}
