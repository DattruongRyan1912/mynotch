import Foundation

/// Cuts a byte stream into messages at newlines, which is how MCP frames JSON-RPC on stdio (and on any byte stream). Bytes
/// arrive in any pieces: a message can come in parts, and a read can hold several.
public struct MCPLineFramer: Sendable {
    public enum Line: Equatable, Sendable {
        case message(Data)
        /// A line longer than the limit. Reported once; the rest of that line is dropped.
        case oversized
    }

    private let maxLength: Int
    private var buffer = Data()
    /// True while the rest of an oversized line is being dropped.
    private var skipping = false

    public init(maxLength: Int = 1 << 20) {
        self.maxLength = maxLength
    }

    /// The lines the new bytes complete. Blank lines are not messages, and a carriage return before the newline is not part
    /// of one.
    public mutating func append(_ data: Data) -> [Line] {
        var lines: [Line] = []
        var rest = data[...]
        while !rest.isEmpty {
            guard let newline = rest.firstIndex(of: UInt8(ascii: "\n")) else {
                if skipping { return lines }
                if buffer.count + rest.count > maxLength {
                    lines.append(.oversized)
                    buffer = Data()
                    skipping = true
                } else {
                    buffer.append(contentsOf: rest)
                }
                return lines
            }
            let chunk = rest[rest.startIndex..<newline]
            rest = rest[(newline + 1)...]
            if skipping {
                skipping = false
            } else if buffer.count + chunk.count > maxLength {
                lines.append(.oversized)
                buffer = Data()
            } else {
                buffer.append(contentsOf: chunk)
                lines += complete()
            }
        }
        return lines
    }

    /// The input ended: what is left, with no newline after it, is the last message.
    public mutating func finish() -> [Line] {
        defer {
            buffer = Data()
            skipping = false
        }
        return skipping ? [] : complete()
    }

    /// The buffered line as a message, unless it is blank.
    private mutating func complete() -> [Line] {
        defer { buffer = Data() }
        var line = buffer[...]
        while line.last == UInt8(ascii: "\r") { line = line.dropLast() }
        guard line.contains(where: { $0 != UInt8(ascii: " ") && $0 != UInt8(ascii: "\t") }) else { return [] }
        return [.message(Data(line))]
    }
}
