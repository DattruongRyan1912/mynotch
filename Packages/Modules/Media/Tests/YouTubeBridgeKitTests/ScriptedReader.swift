import Foundation
@testable import YouTubeBridgeKit

/// A reader that hands out its bytes in pieces of at most `piece`, as a pipe does, then reports the end of input.
final class ScriptedReader: ByteReading {
    private var bytes: Data
    private let piece: Int
    private(set) var reads = 0

    init(_ bytes: Data, piece: Int = .max) {
        self.bytes = bytes
        self.piece = piece
    }

    func read(upTo count: Int) -> Data {
        reads += 1
        let chunk = bytes.prefix(min(count, piece))
        bytes = Data(bytes.dropFirst(chunk.count))
        return Data(chunk)
    }
}

/// What Chrome writes to a native host: the length in the machine's byte order, then the message.
func nativeFrame(_ message: Data) -> Data {
    withUnsafeBytes(of: UInt32(message.count)) { Data($0) } + message
}

func nativeFrame(_ text: String) -> Data {
    nativeFrame(Data(text.utf8))
}
