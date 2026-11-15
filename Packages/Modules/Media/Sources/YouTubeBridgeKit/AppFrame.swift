import Foundation

/// What the host sends the app over the stream socket: a 4-byte big-endian length, then the message's JSON.
public enum AppFrame {
    /// A larger message is dropped by the host, and a larger length makes the app close the connection.
    public static var maxLength: Int { 4 << 20 }

    /// nil when the payload is above `maxLength`.
    public static func encode(_ payload: Data) -> Data? {
        guard payload.count <= maxLength else { return nil }
        return withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) } + payload
    }
}

/// Cuts a byte stream into frames, whatever sizes the bytes arrive in.
public struct AppFrameDecoder {
    public enum Output: Equatable {
        case frame(Data)
        /// The bytes so far do not hold a whole frame.
        case needMore
        /// A length above the decoder's limit (`AppFrame.maxLength` unless it was given another): the stream is out of step, and stays so.
        case tooLarge(Int)
    }

    private var buffer = Data()
    private var failure: Int?
    private let maxLength: Int

    /// - Parameter maxLength: the longest payload that is still a frame; a reader that only expects short messages passes less.
    public init(maxLength: Int = AppFrame.maxLength) {
        self.maxLength = maxLength
    }

    public mutating func append(_ bytes: Data) {
        buffer.append(bytes)
    }

    public mutating func next() -> Output {
        if let failure { return .tooLarge(failure) }
        guard buffer.count >= 4 else { return .needMore }
        let length = buffer.prefix(4).reduce(0) { $0 << 8 | Int($1) }
        guard length <= maxLength else {
            failure = length
            buffer = Data()
            return .tooLarge(length)
        }
        guard buffer.count >= 4 + length else { return .needMore }
        let frame = Data(buffer.dropFirst(4).prefix(length))
        buffer = Data(buffer.dropFirst(4 + length))
        return .frame(frame)
    }
}
