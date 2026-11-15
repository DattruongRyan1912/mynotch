import Foundation

/// What the watcher needs from a tailer; a test can wrap the real one to count reads.
nonisolated protocol LineTailing: AnyObject, Sendable {
    var offset: UInt64 { get }
    var hasMoreToRead: Bool { get }
    func readNewLines(maxBytes: Int) throws -> [String]
}

/// Reads the lines appended to a JSONL file since the previous read, so a transcript that grows while an agent
/// works is parsed once. Not bound to the main actor: the watcher reads from a background queue.
nonisolated final class JSONLTailer: LineTailing, @unchecked Sendable {
    private struct FileIdentity: Equatable {
        var device: dev_t
        var inode: ino_t
    }

    private static let newline = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")

    let url: URL
    /// Serializes every access to the state below, which is what makes `@unchecked Sendable` sound.
    private let queue = DispatchQueue(label: "io.lucasvu.mynotch.aiagents.tailer")
    /// How far the file has been read, including `pending`.
    private var readPosition: UInt64
    /// An unterminated last line: the agent may still be writing it.
    private var pending = Data()
    /// The file read last time; nil until the first read, so a start offset is trusted for the file found then.
    private var identity: FileIdentity?
    /// Whether the last read stopped at `maxBytes` before the end of the file.
    private var hasMore = false

    init(url: URL, startOffset: UInt64 = 0) {
        self.url = url
        readPosition = startOffset
    }

    /// The byte position after the last complete line returned. A tailer created with this start offset
    /// continues without repeating or losing a line, including one that was still incomplete.
    var offset: UInt64 {
        queue.sync { readPosition - UInt64(pending.count) }
    }

    /// True after a `readNewLines(maxBytes:)` that left part of the file unread: call again to continue.
    var hasMoreToRead: Bool {
        queue.sync { hasMore }
    }

    /// Complete, non-empty lines added since the last call. Starts over from the beginning when the file is now
    /// shorter than what was read (truncated) or is a different file at the same path (replaced).
    /// Throws when the file cannot be opened or read, for example while it does not exist.
    /// - Parameter maxBytes: reads at most this much of the file, so a transcript of tens of megabytes is
    ///   processed in bounded pieces; `hasMoreToRead` says whether to call again.
    func readNewLines(maxBytes: Int = .max) throws -> [String] {
        try queue.sync {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var info = stat()
            guard fstat(handle.fileDescriptor, &info) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            let current = FileIdentity(device: info.st_dev, inode: info.st_ino)
            if identity.map({ $0 != current }) == true || UInt64(info.st_size) < readPosition {
                readPosition = 0
                pending = Data()
            }
            identity = current
            try handle.seek(toOffset: readPosition)
            let chunk = try handle.read(upToCount: maxBytes) ?? Data()
            readPosition += UInt64(chunk.count)
            // An empty read means the file shrank since `fstat`; the next call starts over as for any truncation.
            hasMore = !chunk.isEmpty && readPosition < UInt64(info.st_size)
            return lines(completedBy: chunk)
        }
    }

    /// Only `chunk` is searched for line ends, so a long line arriving over many reads stays linear.
    private func lines(completedBy chunk: Data) -> [String] {
        guard let end = chunk.lastIndex(of: Self.newline) else {
            pending.append(chunk)
            return []
        }
        var complete = pending
        complete.append(chunk[..<end])
        pending = Data(chunk[chunk.index(after: end)...])
        return complete.split(separator: Self.newline).compactMap { line in
            let content = line.last == Self.carriageReturn ? line.dropLast() : line
            return content.isEmpty ? nil : String(decoding: content, as: UTF8.self)
        }
    }
}
