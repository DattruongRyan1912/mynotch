import Foundation

/// Splits a byte stream into newline-terminated lines; pipe reads end anywhere, even inside a UTF-8 character.
nonisolated struct LineBuffer {
    private var pending = Data()

    /// Complete non-empty lines finished by `chunk`; the unterminated rest waits for the next chunk.
    mutating func append(_ chunk: Data) -> [String] {
        pending.append(chunk)
        guard let end = pending.lastIndex(of: UInt8(ascii: "\n")) else { return [] }
        let complete = pending[..<end]
        pending = Data(pending[pending.index(after: end)...])
        return complete.split(separator: UInt8(ascii: "\n")).map { String(decoding: $0, as: UTF8.self) }
    }

    /// The unterminated last line once the stream has ended.
    mutating func finish() -> [String] {
        defer { pending = Data() }
        return pending.isEmpty ? [] : [String(decoding: pending, as: UTF8.self)]
    }
}
