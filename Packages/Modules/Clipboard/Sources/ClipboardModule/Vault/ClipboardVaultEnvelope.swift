import Foundation

/// What the header of a vault file says. Everything in it may be read by anyone with the file: the board it belongs to, how it is
/// opened and how many items it holds. The items themselves (and their dates, apps and previews) are only in the sealed part.
nonisolated struct ClipboardVaultEnvelope: Codable, Equatable, Sendable {
    static let formatName = "mynotchvault"
    static let currentVersion = 1

    /// How the password becomes a key. Written with the file so a later version can ask for more rounds.
    struct Derivation: Codable, Equatable, Sendable {
        var algorithm = "pbkdf2-hmac-sha256"
        var iterations: Int
        var salt: Data

        init(iterations: Int, salt: Data) {
            self.iterations = iterations
            self.salt = salt
        }
    }

    var format = ClipboardVaultEnvelope.formatName
    var version = ClipboardVaultEnvelope.currentVersion
    var boardID: UUID
    var method: ClipboardLockMethod
    var itemCount: Int
    /// For a password lock; nil for Touch ID.
    var derivation: Derivation?
    /// The board key under the password's key, for a password lock; nil for Touch ID.
    var wrappedKey: Data?

    init(
        boardID: UUID, method: ClipboardLockMethod, itemCount: Int, derivation: Derivation? = nil, wrappedKey: Data? = nil
    ) {
        self.boardID = boardID
        self.method = method
        self.itemCount = itemCount
        self.derivation = derivation
        self.wrappedKey = wrappedKey
    }

    /// Throws what the user is to be told: a newer version is not "damaged".
    func validate() throws {
        guard format == Self.formatName, version >= 1 else { throw ClipboardVaultError.damaged }
        guard version <= Self.currentVersion else { throw ClipboardVaultError.unsupportedVersion(version) }
        guard (0...ClipboardVaultPayload.maxItems).contains(itemCount) else { throw ClipboardVaultError.damaged }
        switch method {
        case .password:
            guard derivation != nil, wrappedKey != nil else { throw ClipboardVaultError.damaged }
        case .touchID:
            guard derivation == nil, wrappedKey == nil else { throw ClipboardVaultError.damaged }
        }
    }
}

/// A vault file: the header as one line of JSON, a newline, then the sealed bytes as they are (no base64, so a vault of images is
/// not a third bigger). The header can be read alone, so starting the app does not read every vault.
nonisolated struct ClipboardVaultFile: Equatable, Sendable {
    static let fileExtension = "vault"
    /// A header is a few hundred bytes; one that does not end within this is not one.
    static let maxHeaderBytes = 16 * 1024
    static let maxFileBytes = 1 << 30

    var envelope: ClipboardVaultEnvelope
    var sealed: Data

    /// What is known of a vault without being able to open it.
    struct Summary: Equatable, Sendable {
        var boardID: UUID
        var method: ClipboardLockMethod
        var itemCount: Int
    }

    func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Encoding plain values cannot fail.
        var data = (try? encoder.encode(envelope)) ?? Data()
        data.append(0x0A)
        data.append(sealed)
        return data
    }

    static func decode(_ data: Data) throws -> ClipboardVaultFile {
        guard data.count <= maxFileBytes, let newline = data.prefix(maxHeaderBytes + 1).firstIndex(of: 0x0A) else {
            throw ClipboardVaultError.damaged
        }
        let envelope = try header(from: data[data.startIndex..<newline])
        return ClipboardVaultFile(envelope: envelope, sealed: Data(data[(newline + 1)...]))
    }

    private static func header(from data: Data) throws -> ClipboardVaultEnvelope {
        // A header from a later version is told so even when its shape changed.
        struct Version: Decodable { var format: String?; var version: Int? }
        guard let version = try? JSONDecoder().decode(Version.self, from: data), version.format == ClipboardVaultEnvelope.formatName,
              let number = version.version, number >= 1 else { throw ClipboardVaultError.damaged }
        guard number <= ClipboardVaultEnvelope.currentVersion else { throw ClipboardVaultError.unsupportedVersion(number) }
        guard let envelope = try? JSONDecoder().decode(ClipboardVaultEnvelope.self, from: data) else { throw ClipboardVaultError.damaged }
        try envelope.validate()
        return envelope
    }

    static func read(at url: URL) throws -> ClipboardVaultFile {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxFileBytes else { throw ClipboardVaultError.damaged }
        do {
            return try decode(Data(contentsOf: url))
        } catch let error as ClipboardVaultError {
            throw error
        } catch {
            throw ClipboardVaultError.cannotRead(error.localizedDescription)
        }
    }

    /// Reads only the first line.
    static func readHeader(at url: URL) throws -> ClipboardVaultEnvelope {
        try header(from: firstLine(of: url))
    }

    /// Board, method and count, even for a file of a later version that `readHeader` refuses; nil when there is no header at all.
    static func summary(at url: URL) -> Summary? {
        struct Lenient: Decodable { var format: String?; var boardID: UUID?; var method: String?; var itemCount: Int? }
        guard let line = try? firstLine(of: url), let value = try? JSONDecoder().decode(Lenient.self, from: line),
              value.format == ClipboardVaultEnvelope.formatName, let boardID = value.boardID,
              let count = value.itemCount, (0...ClipboardVaultPayload.maxItems).contains(count) else { return nil }
        return Summary(boardID: boardID, method: value.method.flatMap(ClipboardLockMethod.init(rawValue:)) ?? .password, itemCount: count)
    }

    /// Created with mode 0600 from the start, written and flushed under a temporary name, then renamed over the file: a
    /// failed write leaves the old file whole, and no moment leaves it readable by others.
    func write(to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path(percentEncoded: false), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw ClipboardVaultError.cannotWrite(String(cString: strerror(errno))) }
        do {
            try Self.writeAll(encoded(), to: descriptor)
            guard fsync(descriptor) == 0 else { throw ClipboardVaultError.cannotWrite(String(cString: strerror(errno))) }
            close(descriptor)
            guard rename(temporary.path(percentEncoded: false), url.path(percentEncoded: false)) == 0 else {
                throw ClipboardVaultError.cannotWrite(String(cString: strerror(errno)))
            }
        } catch {
            close(descriptor)
            unlink(temporary.path(percentEncoded: false))
            throw error
        }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw ClipboardVaultError.cannotWrite(String(cString: strerror(errno)))
                }
                offset += written
            }
        }
    }

    private static func firstLine(of url: URL) throws -> Data {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ClipboardVaultError.cannotRead(error.localizedDescription)
        }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: maxHeaderBytes + 1), let newline = head.firstIndex(of: 0x0A) else {
            throw ClipboardVaultError.damaged
        }
        return Data(head[head.startIndex..<newline])
    }
}
