import Foundation

/// Wire format sent through the Zero-Knowledge Cloud Relay.
public struct CloudSyncEnvelope: Codable, Sendable {
    public let type: String
    public let v: Int
    public let id: String
    public let senderId: String
    public let timestamp: Int64
    public let nonce: String
    public let tag: String
    public let ciphertext: String

    public init(
        type: String = "clip",
        v: Int = 1,
        id: String = UUID().uuidString,
        senderId: String,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        nonce: String,
        tag: String,
        ciphertext: String
    ) {
        self.type = type
        self.v = v
        self.id = id
        self.senderId = senderId
        self.timestamp = timestamp
        self.nonce = nonce
        self.tag = tag
        self.ciphertext = ciphertext
    }
}

/// The decrypted payload contents of a clipboard entry.
public struct CloudSyncPayload: Codable, Sendable {
    public enum Format: String, Codable, Sendable {
        case plainText = "text/plain"
        case html = "text/html"
        case pngImage = "image/png"
        case uriList = "text/uri-list"
        case octetStream = "application/octet-stream"
    }

    public let format: Format
    public let content: String
    public let sourceApp: String?
    public let timestamp: Int64

    public init(
        format: Format = .plainText,
        content: String,
        sourceApp: String? = nil,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.format = format
        self.content = content
        self.sourceApp = sourceApp
        self.timestamp = timestamp
    }
}

/// Heartbeat ping / pong messages.
public struct CloudSyncHeartbeat: Codable, Sendable {
    public let type: String
    public let timestamp: Int64

    public init(type: String, timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.type = type
        self.timestamp = timestamp
    }
}

/// Status of the cloud sync connection.
public enum CloudSyncStatus: String, Sendable {
    case disconnected = "Ngắt kết nối"
    case connecting = "Đang kết nối..."
    case connected = "Đã kết nối"
    case error = "Lỗi kết nối"
}

// MARK: - CloudSync V2 Protocol Models

/// Wire format for CloudSync V2 with authenticated encryption (AAD).
public struct CloudSyncEnvelopeV2: Codable, Sendable {
    public let type: String
    public let v: Int
    public let id: String
    public let senderId: String
    public let timestamp: Int64
    public let nonce: String
    public let tag: String
    public let ciphertext: String

    public init(
        type: String = "clip_v2",
        v: Int = 2,
        id: String = UUID().uuidString.lowercased(),
        senderId: String,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        nonce: String,
        tag: String,
        ciphertext: String
    ) {
        self.type = type
        self.v = v
        self.id = id
        self.senderId = senderId
        self.timestamp = timestamp
        self.nonce = nonce
        self.tag = tag
        self.ciphertext = ciphertext
    }
}

/// Helper for schema validation of file transfer chunks.
public struct CloudSyncFileChunk: Codable, Sendable {
    public let kind: String
    public let transferId: String
    public let senderSessionId: String
    public let receiverSessionId: String
    public let fileName: String
    public let mimeType: String
    public let fileSize: Int64
    public let fileHash: String
    public let sequence: Int
    public let totalChunks: Int
    public let contentBase64: String

    enum CodingKeys: String, CodingKey {
        case kind
        case transferId = "transfer_id"
        case senderSessionId = "sender_session_id"
        case receiverSessionId = "receiver_session_id"
        case fileName = "file_name"
        case mimeType = "mime_type"
        case fileSize = "file_size"
        case fileHash = "file_hash"
        case sequence
        case totalChunks = "total_chunks"
        case contentBase64 = "content_base64"
    }

    public static func isValid(sequence: Int, totalChunks: Int) -> Bool {
        guard totalChunks > 0 else { return false }
        return sequence >= 0 && sequence < totalChunks
    }
}

