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
