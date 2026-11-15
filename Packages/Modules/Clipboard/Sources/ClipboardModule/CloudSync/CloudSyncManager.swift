import AppKit
import CryptoKit
import Foundation
import MyNotchCore
import Observation
import os

/// Safe asynchronous completer for actor-isolated event callbacks.
@MainActor
final class AsyncCompleter<T: Sendable> {
    private var continuation: CheckedContinuation<T, Never>?
    private var value: T?
    private var isCompleted = false
    private var timeoutTask: Task<Void, Never>?

    func complete(_ val: T) {
        guard !isCompleted else { return }
        isCompleted = true
        value = val
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: val)
        continuation = nil
    }

    func wait(timeoutSeconds: Double, fallback: T) async -> T {
        if isCompleted, let value {
            return value
        }
        return await withCheckedContinuation { cont in
            if isCompleted, let value {
                cont.resume(returning: value)
                return
            }
            self.continuation = cont
            self.timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                if let self, !self.isCompleted {
                    self.complete(fallback)
                }
            }
        }
    }
}

/// Manages the real-time bidirectional WebSocket connection to the Cloud Relay.
@Observable
@MainActor
public final class CloudSyncManager {
    public static let shared = CloudSyncManager()

    public private(set) var status: CloudSyncStatus = .disconnected
    public private(set) var lastSyncDate: Date?
    public private(set) var lastError: String?

    public var config: CloudSyncConfig {
        didSet {
            saveConfig()
            if config.isEnabled {
                reconnect()
            } else {
                disconnect()
            }
        }
    }

    private let log = Logger(subsystem: "io.lucasvu.mynotch", category: "cloud-sync")
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isRunning = false
    public var isRunningState: Bool { isRunning }
    private var reconnectAttempt = 0
    private var heartbeatTask: Task<Void, Never>?

    /// LRU Cache of recent content SHA-256 hashes to prevent echo loops.
    private var recentHashes: [String] = []
    private let maxHashCacheSize = 50

    /// Callback when a new clipboard item is received from Android.
    public var onClipReceived: ((CloudSyncPayload) -> Void)?

    /// Unique session ID generated per connection lifecycle to prevent ACK replay.
    public private(set) var currentSessionId: String = UUID().uuidString.lowercased()
    /// Peer session ID established via hello/ready handshake.
    public private(set) var peerSessionId: String? = nil

    internal func setPeerSessionIdForTesting(_ id: String?) {
        self.peerSessionId = id
    }

    internal var outgoingEnvelopeHandlerForTesting: ((CloudSyncEnvelopeV2, String) -> Void)?

    internal func setConnectedForTesting(
        isRunning: Bool = true,
        peerSessionId: String? = "android-peer-session",
        envelopeHandler: ((CloudSyncEnvelopeV2, String) -> Void)? = nil
    ) {
        if isRunning {
            var cfg = self.config
            if cfg.relayServerUrl.isEmpty {
                cfg.relayServerUrl = "https://127.0.0.1:8789"
            }
            cfg.isEnabled = true
            self.config = cfg
        } else {
            self.config.isEnabled = false
        }
        self.isRunning = isRunning
        self.peerSessionId = peerSessionId
        self.outgoingEnvelopeHandlerForTesting = envelopeHandler
    }

    public struct VerifiedTransferReceipt: Sendable, Equatable {
        public let transferId: String
        public let fileHash: String
        public let senderSessionId: String
        public let savedPath: String

        public init(transferId: String, fileHash: String, senderSessionId: String, savedPath: String) {
            self.transferId = transferId
            self.fileHash = fileHash
            self.senderSessionId = senderSessionId
            self.savedPath = savedPath
        }
    }

    /// Receipt cache of completed transfers storing verified fileHash and senderSessionId to reject replay tampering.
    private var processedReceipts: [String: VerifiedTransferReceipt] = [:]
    private var processedTransferOrder: [String] = []
    private let maxProcessedTransfers = 100

    public func isTransferProcessed(_ transferId: String) -> Bool {
        processedReceipts[transferId] != nil
    }

    public func getProcessedReceipt(_ transferId: String) -> VerifiedTransferReceipt? {
        processedReceipts[transferId]
    }

    private func recordProcessedReceipt(_ receipt: VerifiedTransferReceipt) {
        if processedReceipts[receipt.transferId] != nil { return }
        processedReceipts[receipt.transferId] = receipt
        processedTransferOrder.append(receipt.transferId)
        if processedTransferOrder.count > maxProcessedTransfers {
            let oldest = processedTransferOrder.removeFirst()
            processedReceipts.removeValue(forKey: oldest)
        }
    }

    private init() {
        self.config = Self.loadConfig()
        setupSleepWakeObservers()
        setupDistributedObservers()
        if config.isEnabled {
            connect()
        }
    }

    // MARK: - Lifecycle & Connection

    public func connect() {
        guard config.isEnabled else { return }
        disconnect()

        guard let components = URLComponents(string: config.relayServerUrl),
              let host = components.host, !host.isEmpty else {
            status = .error
            lastError = "URL máy chủ không hợp lệ"
            return
        }

        var wsComponents = components
        if wsComponents.scheme == "http" {
            wsComponents.scheme = "ws"
        } else if wsComponents.scheme == "https" {
            wsComponents.scheme = "wss"
        }
        if wsComponents.path.isEmpty || wsComponents.path == "/" {
            wsComponents.path = "/ws"
        }
        var queryItems = wsComponents.queryItems ?? []
        queryItems.append(URLQueryItem(name: "channel", value: config.channelId))
        queryItems.append(URLQueryItem(name: "auth", value: config.authToken))
        queryItems.append(URLQueryItem(name: "sender", value: "macbook"))
        wsComponents.queryItems = queryItems

        guard let wsUrl = wsComponents.url else {
            status = .error
            lastError = "Không tạo được WebSocket URL"
            return
        }

        status = .connecting
        lastError = nil
        log.info("Connecting to cloud relay: \(wsUrl.host ?? "", privacy: .public)")

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.waitsForConnectivity = true
        urlSession = URLSession(configuration: sessionConfig)
        webSocketTask = urlSession?.webSocketTask(with: wsUrl)
        webSocketTask?.resume()

        isRunning = true
        status = .connected
        reconnectAttempt = 0
        sendHello()
        startListening()
        startHeartbeat()
    }

    public func disconnect() {
        isRunning = false
        heartbeatTask?.cancel()
        heartbeatTask = nil

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        resetSession()
        status = .disconnected
    }

    public func reconnect() {
        disconnect()
        connect()
    }

    // MARK: - Send Clipboard to Cloud (Mac -> Android)

    /// Encrypts and transmits a new clipboard item copied on macOS to Android (Legacy V1).
    public func sendClip(text: String, sourceApp: String? = nil) {
        guard isRunning, config.isEnabled, let webSocketTask else { return }

        // Compute content hash and store in LRU to avoid processing if echoed
        let hash = computeHash(text)
        recordHash(hash)

        let payload = CloudSyncPayload(format: .plainText, content: text, sourceApp: sourceApp)

        guard let key = try? CloudSyncCrypto.importKeyBase64(config.aesKeyBase64),
              let envelope = try? CloudSyncCrypto.encrypt(payload: payload, using: key, senderId: "macbook"),
              let data = try? JSONEncoder().encode(envelope),
              let jsonString = String(data: data, encoding: .utf8) else {
            log.error("Failed to encrypt clipboard envelope")
            return
        }

        webSocketTask.send(.string(jsonString)) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.log.error("Failed to send clip envelope: \(error.localizedDescription, privacy: .public)")
                } else {
                    self?.lastSyncDate = Date()
                    self?.log.notice("Successfully relayed encrypted clip to cloud")
                }
            }
        }
    }

    // MARK: - Send V2 Multi-Format / Files (Mac -> Android)

    /// Sends a plain text clip using V2 protocol.
    public func sendClipV2(text: String, sourceApp: String? = nil) {
        let payloadObj: [String: Any] = [
            "kind": "text",
            "content": text,
            "sourceApp": sourceApp ?? "Mac",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        sendPayloadV2(payloadObj)
    }

    /// Sends a web link using V2 protocol.
    public func sendLinkV2(url: URL, sourceApp: String? = nil) {
        let payloadObj: [String: Any] = [
            "kind": "link",
            "content": url.absoluteString,
            "sourceApp": sourceApp ?? "Mac",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        sendPayloadV2(payloadObj)
    }

    /// Sends an image using V2 protocol.
    @discardableResult
    public func sendImageV2(
        imageData: Data,
        fileName: String,
        width: Int,
        height: Int,
        sourceApp: String? = nil
    ) -> Task<Bool, Never> {
        let transferId = UUID().uuidString.lowercased()
        let fileHash = SHA256.hash(data: imageData).compactMap { String(format: "%02x", $0) }.joined()

        return Task { @MainActor [weak self] in
            guard let self else { return false }
            if self.peerSessionId == nil {
                self.sendHello()
                for _ in 0..<30 {
                    if self.peerSessionId != nil { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            guard let receiverSessionId = self.peerSessionId, !receiverSessionId.isEmpty else {
                self.log.error("Cannot send image: peer session not established (handshake incomplete)")
                return false
            }
            let senderSessionId = self.currentSessionId

            let payloadObj: [String: Any] = [
                "kind": "image",
                "transfer_id": transferId,
                "sender_session_id": senderSessionId,
                "receiver_session_id": receiverSessionId,
                "file_hash": fileHash,
                "content_base64": imageData.base64EncodedString(),
                "mime_type": "image/png",
                "file_name": fileName,
                "width": width,
                "height": height,
                "byte_count": imageData.count,
                "sourceApp": sourceApp ?? "Mac",
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]

            let completeCompleter = AsyncCompleter<Bool>()
            self.completeAckWaiters[transferId] = (expectedHash: fileHash, expectedSessionId: senderSessionId, completer: completeCompleter)

            self.sendPayloadV2(payloadObj)

            let completeAcked = await completeCompleter.wait(timeoutSeconds: 30.0, fallback: false)
            self.completeAckWaiters.removeValue(forKey: transferId)
            if completeAcked {
                self.log.notice("Image \(fileName) delivery confirmed via complete_ack")
            } else {
                self.log.error("Image \(fileName) transfer timed out or hash mismatch waiting for complete_ack")
            }
            return completeAcked
        }
    }

    /// Sends a regular file using V2 protocol (inline if <= 1 MiB, chunked otherwise up to 15 MiB).
    @discardableResult
    public func sendFileV2(fileURL: URL, sourceApp: String? = nil) -> Task<Bool, Never> {
        let fileName = fileURL.lastPathComponent
        guard CloudSyncFileStore.isSafeFileName(fileName) else {
            log.error("Unsafe file name rejected: \(fileName, privacy: .public)")
            return Task { false }
        }

        // Fast attribute check without loading entire file into memory
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let rawSize = attrs[.size] as? NSNumber else {
            log.error("Failed to read file attributes for: \(fileURL.path, privacy: .public)")
            return Task { false }
        }
        let fileSize = rawSize.int64Value
        guard CloudSyncFileTransfer.isFileSizeAllowed(fileSize: fileSize) else {
            log.error("File size (\(fileSize) bytes) exceeds 15 MiB limit")
            return Task { false }
        }

        let app = sourceApp ?? "Mac"
        return Task.detached(priority: .userInitiated) { [weak self] () -> Bool in
            guard let self else { return false }
            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
            } catch {
                return false
            }
            let actualSize = Int64(data.count)
            guard actualSize >= 0 && actualSize <= CloudSyncFileTransfer.maxFileSizeBytes else { return false }
            let fileHash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
            let transferId = UUID().uuidString.lowercased()
            let totalChunks = CloudSyncFileTransfer.calculateChunkCount(fileSize: actualSize)

            return await self.dispatchPreparedFile(
                transferId: transferId,
                fileName: fileName,
                fileSize: actualSize,
                fileHash: fileHash,
                totalChunks: totalChunks,
                data: data,
                filePath: fileURL.path,
                app: app
            )
        }
    }

    @MainActor
    private func dispatchPreparedFile(
        transferId: String,
        fileName: String,
        fileSize: Int64,
        fileHash: String,
        totalChunks: Int,
        data: Data,
        filePath: String,
        app: String
    ) async -> Bool {
        if self.peerSessionId == nil {
            self.sendHello()
            for _ in 0..<30 {
                if self.peerSessionId != nil { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        guard let receiverSessionId = self.peerSessionId, !receiverSessionId.isEmpty else {
            self.log.error("Cannot send file: peer session not established (handshake incomplete)")
            return false
        }
        let senderSessionId = self.currentSessionId

        // Register complete_ack waiter BEFORE sending any chunks (prevent race condition)
        let completeCompleter = AsyncCompleter<Bool>()
        self.completeAckWaiters[transferId] = (expectedHash: fileHash, expectedSessionId: senderSessionId, completer: completeCompleter)

        if totalChunks == 1 {
            // Inline file
            let payloadObj: [String: Any] = [
                "kind": "file",
                "transfer_id": transferId,
                "sender_session_id": senderSessionId,
                "receiver_session_id": receiverSessionId,
                "file_name": fileName,
                "mime_type": "application/octet-stream",
                "file_size": fileSize,
                "file_hash": fileHash,
                "sequence": 0,
                "total_chunks": 1,
                "content_base64": data.base64EncodedString(),
                "sourceApp": app,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]
            self.sendPayloadV2(payloadObj)
        } else {
            // Chunked transfer (512 KiB per chunk) with Window = 1 Flow Control
            let chunkSize = CloudSyncFileTransfer.chunkSizeBytes
            for seq in 0..<totalChunks {
                let start = seq * chunkSize
                guard start < data.count else { break }
                let end = min(start + chunkSize, data.count)
                let chunkData = data.subdata(in: start..<end)

                let payloadObj: [String: Any] = [
                    "kind": "file_chunk",
                    "transfer_id": transferId,
                    "sender_session_id": senderSessionId,
                    "receiver_session_id": receiverSessionId,
                    "file_name": fileName,
                    "mime_type": "application/octet-stream",
                    "file_size": fileSize,
                    "file_hash": fileHash,
                    "sequence": seq,
                    "total_chunks": totalChunks,
                    "content_base64": chunkData.base64EncodedString(),
                    "sourceApp": app,
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ]

                let key = "\(transferId)_\(seq)"
                let chunkCompleter = AsyncCompleter<Bool>()
                self.chunkAckWaiters[key] = chunkCompleter

                self.sendPayloadV2(payloadObj)

                // Window = 1 Flow Control: wait for chunk_ack before sending next chunk
                let chunkAcked = await chunkCompleter.wait(timeoutSeconds: 15.0, fallback: false)
                self.chunkAckWaiters.removeValue(forKey: key)
                guard chunkAcked else {
                    self.log.error("Transfer \(transferId) failed: chunk \(seq) ACK timeout or mismatch")
                    self.completeAckWaiters.removeValue(forKey: transferId)
                    return false
                }
            }
        }

        // Await complete_ack receipt
        let completeAcked = await completeCompleter.wait(timeoutSeconds: 30.0, fallback: false)
        self.completeAckWaiters.removeValue(forKey: transferId)
        if completeAcked {
            self.log.notice("File \(fileName) delivery confirmed via complete_ack")
            let receipt = VerifiedTransferReceipt(
                transferId: transferId,
                fileHash: fileHash,
                senderSessionId: senderSessionId,
                savedPath: filePath
            )
            recordProcessedReceipt(receipt)
        } else {
            self.log.error("File \(fileName) transfer timed out or hash mismatch waiting for complete_ack")
        }
        return completeAcked
    }

    private func sendPayloadV2(_ payloadObj: [String: Any]) {
        guard isRunning, config.isEnabled, (webSocketTask != nil || outgoingEnvelopeHandlerForTesting != nil) else { return }
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payloadObj),
              let key = try? CloudSyncCrypto.importKeyBase64(config.aesKeyBase64),
              let envelopeV2 = try? CloudSyncCrypto.encryptV2(plaintext: payloadData, using: key, senderId: "macbook"),
              let data = try? JSONEncoder().encode(envelopeV2),
              let jsonString = String(data: data, encoding: .utf8) else {
            log.error("Failed to encrypt v2 payload envelope")
            return
        }

        // Enforce 2 MiB wire ceiling
        guard jsonString.utf8.count <= 2 * 1024 * 1024 else {
            log.error("Envelope size (\(jsonString.utf8.count) bytes) exceeds relay ceiling of 2 MiB")
            return
        }

        if let handler = outgoingEnvelopeHandlerForTesting {
            lastSyncDate = Date()
            handler(envelopeV2, jsonString)
            return
        }

        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.log.error("Failed to send v2 envelope: \(error.localizedDescription, privacy: .public)")
                } else {
                    self?.lastSyncDate = Date()
                    self?.log.notice("Successfully relayed encrypted v2 payload to cloud")
                }
            }
        }
    }

    // MARK: - Receive Clipboard from Cloud (Android -> Mac)

    private func startListening() {
        guard isRunning, let webSocketTask else { return }

        webSocketTask.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.isRunning else { return }

                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.startListening() // Continue listening loop

                case .failure(let error):
                    self.log.error("WebSocket receive error: \(error.localizedDescription, privacy: .public)")
                    self.scheduleReconnect()
                }
            }
        }
    }

    private var fileAssemblers: [String: CloudSyncChunkAssembler] = [:]
    private var assemblerTimestamps: [String: Date] = [:]
    private let fileStore = CloudSyncFileStore()
    var chunkAckWaiters: [String: AsyncCompleter<Bool>] = [:]
    var completeAckWaiters: [String: (expectedHash: String, expectedSessionId: String?, completer: AsyncCompleter<Bool>)] = [:]

    private func resetSession() {
        currentSessionId = UUID().uuidString.lowercased()
        peerSessionId = nil
        for (_, completer) in chunkAckWaiters {
            completer.complete(false)
        }
        chunkAckWaiters.removeAll()
        for (_, entry) in completeAckWaiters {
            entry.completer.complete(false)
        }
        completeAckWaiters.removeAll()
        fileAssemblers.removeAll()
        assemblerTimestamps.removeAll()
    }

    private func sendHello() {
        let helloObj: [String: Any] = [
            "kind": "hello",
            "session_id": currentSessionId,
            "senderId": "macbook",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        sendPayloadV2(helloObj)
    }

    @MainActor
    func waitForChunkAck(transferId: String, sequence: Int, timeoutSeconds: Double = 15.0) async -> Bool {
        let key = "\(transferId)_\(sequence)"
        if let existing = chunkAckWaiters[key] {
            return await existing.wait(timeoutSeconds: timeoutSeconds, fallback: false)
        }
        let completer = AsyncCompleter<Bool>()
        chunkAckWaiters[key] = completer
        let result = await completer.wait(timeoutSeconds: timeoutSeconds, fallback: false)
        chunkAckWaiters.removeValue(forKey: key)
        return result
    }

    @MainActor
    func waitForCompleteAck(transferId: String, expectedHash: String, timeoutSeconds: Double = 30.0) async -> Bool {
        if let existing = completeAckWaiters[transferId] {
            return await existing.completer.wait(timeoutSeconds: timeoutSeconds, fallback: false)
        }
        let completer = AsyncCompleter<Bool>()
        completeAckWaiters[transferId] = (expectedHash: expectedHash, expectedSessionId: nil, completer: completer)
        let result = await completer.wait(timeoutSeconds: timeoutSeconds, fallback: false)
        completeAckWaiters.removeValue(forKey: transferId)
        return result
    }

    private func sendChunkAck(transferId: String, sequence: Int) {
        let ackObj: [String: Any] = [
            "kind": "chunk_ack",
            "transfer_id": transferId,
            "sequence": sequence,
            "status": "ok"
        ]
        sendPayloadV2(ackObj)
    }

    private func sendCompleteAck(transferId: String, fileHash: String, senderSessionId: String?) {
        let ackObj: [String: Any] = [
            "kind": "complete_ack",
            "transfer_id": transferId,
            "sender_session_id": senderSessionId ?? "",
            "receiver_session_id": currentSessionId,
            "file_hash": fileHash,
            "status": "success",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        sendPayloadV2(ackObj)
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8) else { return }

        // Check if message is CloudSync V2
        if let envelopeV2 = try? JSONDecoder().decode(CloudSyncEnvelopeV2.self, from: data), envelopeV2.type == "clip_v2" {
            handleMessageV2(envelopeV2)
            return
        }

        // Try decoding legacy envelope V1
        guard let envelope = try? JSONDecoder().decode(CloudSyncEnvelope.self, from: data) else {
            return
        }

        // Avoid handling clips we originated ourselves
        if envelope.senderId == "macbook" { return }

        guard let key = try? CloudSyncCrypto.importKeyBase64(config.aesKeyBase64),
              let payload = try? CloudSyncCrypto.decrypt(envelope: envelope, using: key) else {
            log.error("Failed to decrypt incoming envelope from \(envelope.senderId, privacy: .public)")
            return
        }

        // Check if content hash was already recently handled
        let hash = computeHash(payload.content)
        if isRecentlyHandled(hash) { return }
        recordHash(hash)

        // Write directly to NSPasteboard with OwnPasteboardWrite marker
        writeToPasteboard(payload.content)
        lastSyncDate = Date()
        onClipReceived?(payload)
        log.notice("Received clip from \(envelope.senderId, privacy: .public) (\(payload.content.count) chars)")
    }

    func handleMessageV2(_ envelope: CloudSyncEnvelopeV2) {
        if envelope.senderId == "macbook" { return }
        guard let key = try? CloudSyncCrypto.importKeyBase64(config.aesKeyBase64),
              let plaintextData = try? CloudSyncCrypto.decryptV2(envelope: envelope, using: key),
              let json = try? JSONSerialization.jsonObject(with: plaintextData) as? [String: Any],
              let kind = json["kind"] as? String else {
            log.error("Failed to decrypt or decode incoming V2 envelope from \(envelope.senderId, privacy: .public)")
            return
        }

        switch kind {
        case "hello":
            if let sId = json["session_id"] as? String, !sId.isEmpty {
                let isTransient = json["transient"] as? Bool ?? false
                if !isTransient {
                    self.peerSessionId = sId
                }
                let readyObj: [String: Any] = [
                    "kind": "ready",
                    "session_id": currentSessionId,
                    "peer_session_id": sId,
                    "senderId": "macbook",
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ]
                sendPayloadV2(readyObj)
            }
        case "ready":
            if let sId = json["session_id"] as? String, !sId.isEmpty {
                self.peerSessionId = sId
            }
        case "chunk_ack":
            guard let transferId = json["transfer_id"] as? String,
                  let seq = json["sequence"] as? Int else { return }
            let key = "\(transferId)_\(seq)"
            if let completer = chunkAckWaiters[key] {
                completer.complete(true)
            }
        case "complete_ack":
            guard let transferId = json["transfer_id"] as? String else { return }
            let fileHash = json["file_hash"] as? String ?? ""
            let status = json["status"] as? String ?? ""
            let ackSenderSession = json["sender_session_id"] as? String
            if let entry = completeAckWaiters[transferId] {
                let hashValid = !entry.expectedHash.isEmpty && fileHash == entry.expectedHash
                let sessionValid: Bool
                if let expected = entry.expectedSessionId {
                    sessionValid = (ackSenderSession != nil && !ackSenderSession!.isEmpty && ackSenderSession == expected)
                } else {
                    sessionValid = true
                }
                let success = status == "success" && hashValid && sessionValid
                entry.completer.complete(success)
            }
        case "text":
            if let content = json["content"] as? String {
                writeToPasteboard(content)
                lastSyncDate = Date()
                let payload = CloudSyncPayload(format: .plainText, content: content, sourceApp: json["sourceApp"] as? String)
                onClipReceived?(payload)
            }
        case "link":
            if let content = json["content"] as? String, let url = URL(string: content) {
                writeURLToPasteboard(url)
                lastSyncDate = Date()
                let payload = CloudSyncPayload(format: .uriList, content: content, sourceApp: json["sourceApp"] as? String)
                onClipReceived?(payload)
            }
        case "image":
            if let contentBase64 = json["content_base64"] as? String,
               let imgData = Data(base64Encoded: contentBase64) {
                let transferId = json["transfer_id"] as? String
                let fileHash = json["file_hash"] as? String ?? ""
                let senderSession = json["sender_session_id"] as? String

                guard let targetReceiverSession = json["receiver_session_id"] as? String,
                      !targetReceiverSession.isEmpty,
                      targetReceiverSession == currentSessionId else {
                    log.warning("Missing or mismatched receiver_session_id for image, rejecting")
                    return
                }

                if let transferId, let receipt = processedReceipts[transferId] {
                    if !fileHash.isEmpty && fileHash != receipt.fileHash {
                        log.error("Replay tampering detected: incoming hash \(fileHash) != original \(receipt.fileHash)")
                        return
                    }
                    log.notice("Image transfer \(transferId, privacy: .public) already processed (replay ignored)")
                    sendCompleteAck(transferId: transferId, fileHash: receipt.fileHash, senderSessionId: receipt.senderSessionId)
                    return
                }

                writeImageToPasteboard(imgData)
                lastSyncDate = Date()
                let payload = CloudSyncPayload(format: .pngImage, content: contentBase64, sourceApp: json["sourceApp"] as? String)
                onClipReceived?(payload)
                if let transferId {
                    let receipt = VerifiedTransferReceipt(transferId: transferId, fileHash: fileHash, senderSessionId: senderSession ?? "", savedPath: "")
                    recordProcessedReceipt(receipt)
                    sendCompleteAck(transferId: transferId, fileHash: receipt.fileHash, senderSessionId: receipt.senderSessionId)
                }
            }
        case "file", "file_chunk":
            handleIncomingFileChunk(json)
        default:
            break
        }
    }

    private func handleIncomingFileChunk(_ json: [String: Any]) {
        guard let transferId = json["transfer_id"] as? String,
              let fileName = json["file_name"] as? String,
              let mimeType = json["mime_type"] as? String,
              let fileSize = json["file_size"] as? Int64,
              let fileHash = json["file_hash"] as? String,
              let seq = json["sequence"] as? Int,
              let totalChunks = json["total_chunks"] as? Int,
              let contentBase64 = json["content_base64"] as? String,
              let chunkData = Data(base64Encoded: contentBase64) else {
            return
        }

        guard let targetReceiverSession = json["receiver_session_id"] as? String,
              !targetReceiverSession.isEmpty,
              targetReceiverSession == currentSessionId else {
            log.warning("Missing or mismatched receiver_session_id for file: \(json["receiver_session_id"] as? String ?? "nil") != \(self.currentSessionId), rejecting")
            return
        }

        // Anti-Replay: if transfer was already completed and saved, re-emit complete_ack and ignore duplicate chunks
        if let receipt = processedReceipts[transferId] {
            if !fileHash.isEmpty && fileHash != receipt.fileHash {
                log.error("Replay tampering detected: incoming hash \(fileHash) != original \(receipt.fileHash)")
                return
            }
            log.notice("File transfer \(transferId, privacy: .public) already processed (replay ignored)")
            sendCompleteAck(transferId: transferId, fileHash: receipt.fileHash, senderSessionId: receipt.senderSessionId)
            return
        }

        // Validate metadata consistency if assembler exists
        if let existing = fileAssemblers[transferId] {
            if existing.fileName != fileName || existing.fileSize != fileSize ||
               existing.fileHash != fileHash || existing.totalChunks != totalChunks {
                log.error("Metadata inconsistency for transfer \(transferId), aborting")
                fileAssemblers.removeValue(forKey: transferId)
                assemblerTimestamps.removeValue(forKey: transferId)
                return
            }
        }

        // Prune stale chunk assemblies (>120s timeout) and bound capacity to max 10
        let now = Date()
        assemblerTimestamps[transferId] = now
        let staleThreshold = now.addingTimeInterval(-120)
        for (tid, timestamp) in assemblerTimestamps where timestamp < staleThreshold {
            fileAssemblers.removeValue(forKey: tid)
            assemblerTimestamps.removeValue(forKey: tid)
        }
        if fileAssemblers[transferId] == nil && fileAssemblers.count >= 10 {
            if let oldest = assemblerTimestamps.min(by: { $0.value < $1.value }) {
                fileAssemblers.removeValue(forKey: oldest.key)
                assemblerTimestamps.removeValue(forKey: oldest.key)
            }
        }

        var assembler = fileAssemblers[transferId] ?? CloudSyncChunkAssembler(
            transferId: transferId,
            fileName: fileName,
            mimeType: mimeType,
            fileSize: fileSize,
            fileHash: fileHash,
            totalChunks: totalChunks
        )

        do {
            try assembler.addChunk(sequence: seq, data: chunkData)
            fileAssemblers[transferId] = assembler
            sendChunkAck(transferId: transferId, sequence: seq)

            if assembler.isComplete {
                let completeData = try assembler.finalizeAndVerify()
                let savedURL = try fileStore.saveReceivedFile(data: completeData, fileName: fileName, transferId: transferId)
                writeFileURLToPasteboard(savedURL)
                fileAssemblers.removeValue(forKey: transferId)
                assemblerTimestamps.removeValue(forKey: transferId)
                let receipt = VerifiedTransferReceipt(
                    transferId: transferId,
                    fileHash: fileHash,
                    senderSessionId: json["sender_session_id"] as? String ?? "",
                    savedPath: savedURL.path
                )
                recordProcessedReceipt(receipt)
                sendCompleteAck(transferId: transferId, fileHash: receipt.fileHash, senderSessionId: receipt.senderSessionId)
                lastSyncDate = Date()
                log.notice("Saved received file to \(savedURL.path, privacy: .public)")
                let payload = CloudSyncPayload(format: .octetStream, content: savedURL.path, sourceApp: json["sourceApp"] as? String)
                onClipReceived?(payload)
            }
        } catch {
            log.error("Failed assembling file chunks: \(error.localizedDescription, privacy: .public)")
            fileAssemblers.removeValue(forKey: transferId)
            assemblerTimestamps.removeValue(forKey: transferId)
        }
    }

    private func writeURLToPasteboard(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.URL, .string, OwnPasteboardWrite.pasteboardType], owner: nil)
        (url as NSURL).write(to: pasteboard)
        pasteboard.setString(url.absoluteString, forType: .string)
        pasteboard.setData(Data(), forType: OwnPasteboardWrite.pasteboardType)
    }

    private func writeImageToPasteboard(_ data: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, OwnPasteboardWrite.pasteboardType], owner: nil)
        pasteboard.setData(data, forType: .png)
        pasteboard.setData(Data(), forType: OwnPasteboardWrite.pasteboardType)
    }

    private func writeFileURLToPasteboard(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.fileURL, .string, OwnPasteboardWrite.pasteboardType], owner: nil)
        (url as NSURL).write(to: pasteboard)
        pasteboard.setString(url.path, forType: .string)
        pasteboard.setData(Data(), forType: OwnPasteboardWrite.pasteboardType)
    }

    private func writeToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // Add OwnPasteboardWrite marker to prevent ClipboardMonitor from echoing
        pasteboard.declareTypes([.string, OwnPasteboardWrite.pasteboardType], owner: nil)
        pasteboard.setString(string, forType: .string)
        pasteboard.setData(Data(), forType: OwnPasteboardWrite.pasteboardType)
    }

    // MARK: - Heartbeat & Auto-reconnect

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, self.isRunning, let task = self.webSocketTask else { break }
                let ping = CloudSyncHeartbeat(type: "ping")
                if let data = try? JSONEncoder().encode(ping),
                   let json = String(data: data, encoding: .utf8) {
                    task.send(.string(json)) { _ in }
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard isRunning else { return }
        status = .connecting
        reconnectAttempt += 1

        let delaySeconds = min(Double(1 << min(reconnectAttempt, 5)), 30.0)
        log.notice("Scheduling reconnect in \(delaySeconds)s (attempt \(self.reconnectAttempt))")

        Task {
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard self.isRunning else { return }
            self.connect()
        }
    }

    // MARK: - Sleep / Wake Observers

    private func setupSleepWakeObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.disconnect()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.config.isEnabled == true {
                    self?.connect()
                }
            }
        }
    }

    // MARK: - Distributed Notification Observers (Inter-Process & On-Demand Triggers)

    private final class DistributedObserverTarget: NSObject {
        private let handler: (Notification) -> Void

        init(handler: @escaping (Notification) -> Void) {
            self.handler = handler
            super.init()
        }

        @objc func onNotification(_ note: Notification) {
            handler(note)
        }
    }

    private var distributedObserverTarget: DistributedObserverTarget?

    private func setupDistributedObservers() {
        let target = DistributedObserverTarget { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // 1. Feature Flag: Test IPC hook is strictly disabled by default in production
                guard UserDefaults.standard.bool(forKey: "MyNotch.Clipboard.CloudSyncTestIpcEnabled") else {
                    self.log.error("[DIST-NOTE] Rejected: MyNotch.Clipboard.CloudSyncTestIpcEnabled is disabled")
                    return
                }

                // 2. Authentication: Caller must provide authToken matching configured secret
                guard let token = note.userInfo?["authToken"] as? String,
                      !token.isEmpty,
                      token == self.config.authToken else {
                    self.log.error("[DIST-NOTE] Rejected: missing or invalid authToken")
                    return
                }

                // 3. Operational State
                guard self.isRunning, self.config.isEnabled else {
                    self.log.warning("[DIST-NOTE] Rejected: CloudSyncManager is not running or disabled")
                    return
                }

                // 4. Sensitive item guard
                if let sensitive = note.userInfo?["sensitive"] as? Bool, sensitive {
                    self.log.error("[DIST-NOTE] Rejected: sensitive items cannot be sent to cloud")
                    return
                }

                let filePath = note.userInfo?["filePath"] as? String
                let imagePath = note.userInfo?["imagePath"] as? String
                let text = note.userInfo?["text"] as? String
                let link = note.userInfo?["link"] as? String

                if let filePath {
                    // 5. Path traversal guard
                    guard !filePath.contains("..") else {
                        self.log.error("[DIST-NOTE] Rejected: path traversal detected in filePath: \(filePath)")
                        return
                    }
                    let fileURL = URL(fileURLWithPath: filePath).resolvingSymlinksInPath()
                    guard FileManager.default.fileExists(atPath: fileURL.path) else {
                        self.log.error("[DIST-NOTE] Rejected: file does not exist at \(fileURL.path)")
                        return
                    }
                    guard let attr = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                          let size = attr[.size] as? Int64 else {
                        self.log.error("[DIST-NOTE] Rejected: cannot read file attributes at \(fileURL.path)")
                        return
                    }
                    // 6. Size guard: Max 15 MiB
                    guard CloudSyncFileTransfer.isFileSizeAllowed(fileSize: size) else {
                        self.log.error("[DIST-NOTE] Rejected: file size \(size) exceeds 15 MiB limit")
                        return
                    }

                    self.log.notice("[DIST-NOTE] Authenticated sendFileV2 for \(fileURL.path) (\(size) bytes)")
                    let task = self.sendFileV2(fileURL: fileURL, sourceApp: "MyNotch")
                    let success = await task.value
                    self.log.notice("[DIST-NOTE] sendFileV2 completed: \(success)")

                } else if let imagePath {
                    // Path traversal guard
                    guard !imagePath.contains("..") else {
                        self.log.error("[DIST-NOTE] Rejected: path traversal detected in imagePath: \(imagePath)")
                        return
                    }
                    let imgURL = URL(fileURLWithPath: imagePath).resolvingSymlinksInPath()
                    guard FileManager.default.fileExists(atPath: imgURL.path) else {
                        self.log.error("[DIST-NOTE] Rejected: image does not exist at \(imgURL.path)")
                        return
                    }
                    guard let attr = try? FileManager.default.attributesOfItem(atPath: imgURL.path),
                          let size = attr[.size] as? Int64,
                          CloudSyncFileTransfer.isFileSizeAllowed(fileSize: size) else {
                        self.log.error("[DIST-NOTE] Rejected: image size exceeds 15 MiB limit or unreadable")
                        return
                    }
                    guard let imgData = try? Data(contentsOf: imgURL),
                          let img = NSImage(data: imgData) else {
                        self.log.error("[DIST-NOTE] Rejected: cannot decode image at \(imgURL.path)")
                        return
                    }

                    self.log.notice("[DIST-NOTE] Authenticated sendImageV2 for \(imgURL.path)")
                    let task = self.sendImageV2(
                        imageData: imgData,
                        fileName: imgURL.lastPathComponent,
                        width: Int(img.size.width),
                        height: Int(img.size.height),
                        sourceApp: "MyNotch"
                    )
                    let success = await task.value
                    self.log.notice("[DIST-NOTE] sendImageV2 completed: \(success)")

                } else if let text {
                    self.log.notice("[DIST-NOTE] Authenticated sendClipV2: \(text.prefix(30))")
                    self.sendClipV2(text: text, sourceApp: "MyNotch")

                } else if let link, let url = URL(string: link), url.scheme == "http" || url.scheme == "https" {
                    self.log.notice("[DIST-NOTE] Authenticated sendLinkV2: \(link)")
                    self.sendLinkV2(url: url, sourceApp: "MyNotch")
                }
            }
        }
        self.distributedObserverTarget = target
        DistributedNotificationCenter.default().addObserver(
            target,
            selector: #selector(DistributedObserverTarget.onNotification(_:)),
            name: NSNotification.Name("io.lucasvu.mynotch.cloudSyncSend"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    // MARK: - Echo Loop Prevention Cache

    private func computeHash(_ content: String) -> String {
        let digest = SHA256.hash(data: Data(content.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func isRecentlyHandled(_ hash: String) -> Bool {
        recentHashes.contains(hash)
    }

    private func recordHash(_ hash: String) {
        if !recentHashes.contains(hash) {
            recentHashes.append(hash)
            if recentHashes.count > maxHashCacheSize {
                recentHashes.removeFirst()
            }
        }
    }

    // MARK: - Config Persistence

    private static let defaultsKey = "MyNotch.Clipboard.CloudSyncConfig"

    private static func loadConfig() -> CloudSyncConfig {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let config = try? JSONDecoder().decode(CloudSyncConfig.self, from: data) else {
            return CloudSyncConfig()
        }
        return config
    }

    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
