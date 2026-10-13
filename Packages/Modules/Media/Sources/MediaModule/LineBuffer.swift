import Foundation

/// Splits a byte stream into newline-terminated lines; pipe reads end anywhere, even inside a UTF-8 character.
nonisolated struct LineBuffer {
    private static let newline = UInt8(ascii: "\n")
    private var pending = Data()

    /// Complete non-empty lines finished by `chunk`; the unterminated rest waits for the next chunk.
    /// Only `chunk` is searched, so a long line (artwork is hundreds of KB) arriving in many chunks stays linear.
    mutating func append(_ chunk: Data) -> [String] {
        guard let end = chunk.lastIndex(of: Self.newline) else {
            pending.append(chunk)
            return []
        }
        pending.append(chunk[..<end])
        let complete = pending
        pending = Data(chunk[chunk.index(after: end)...])
        return complete.split(separator: Self.newline).map { String(decoding: $0, as: UTF8.self) }
    }

    /// The unterminated last line once the stream has ended.
    mutating func finish() -> [String] {
        defer { pending = Data() }
        return pending.isEmpty ? [] : [String(decoding: pending, as: UTF8.self)]
    }
}
