import Foundation

/// Where bytes come from: a pipe, or a script in a test.
public protocol ByteReading {
    /// At most `count` bytes, waiting until there are some. Empty at the end of the input, and on an error.
    func read(upTo count: Int) -> Data
}

/// A file descriptor read with `read(2)`, which hands back what is there instead of waiting for `count` bytes the
/// way `FileHandle` does on a pipe.
public struct FileDescriptorReader: ByteReading {
    public let fileDescriptor: Int32

    public init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    public func read(upTo count: Int) -> Data {
        var buffer = [UInt8](repeating: 0, count: count)
        while true {
            let received = Foundation.read(fileDescriptor, &buffer, count)
            if received >= 0 { return Data(buffer[0..<received]) }
            if errno != EINTR { return Data() }
        }
    }
}

/// Reads Chrome's native messaging stream: each message is a 4-byte length in the machine's byte order, then that
/// many bytes of JSON.
public struct NativeMessageReader<Source: ByteReading> {
    public enum Result: Equatable {
        case message(Data)
        /// The length is more than Chrome ever sends, so the stream is out of step and cannot be read on.
        case tooLarge(Int)
        /// The input ended, in the middle of a message or not.
        case end
    }

    /// What Chrome allows an extension to send a host.
    public static var maxLength: Int { 64 << 20 }
    /// A message is read in pieces of this size, so a made-up length reserves no memory before the data is there.
    private static var chunkSize: Int { 64 << 10 }

    private let source: Source

    public init(source: Source) {
        self.source = source
    }

    public mutating func next() -> Result {
        guard let header = readExactly(4) else { return .end }
        let length = Int(header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        guard length <= Self.maxLength else { return .tooLarge(length) }
        guard let body = readExactly(length) else { return .end }
        return .message(body)
    }

    private func readExactly(_ count: Int) -> Data? {
        var data = Data()
        while data.count < count {
            let piece = source.read(upTo: min(count - data.count, Self.chunkSize))
            if piece.isEmpty { return nil }
            data.append(piece)
        }
        return data
    }
}
