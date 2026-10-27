import AppKit
import CryptoKit
import Foundation
import MyNotchCore
import Observation
import os

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
    private var reconnectAttempt = 0
    private var heartbeatTask: Task<Void, Never>?

    /// LRU Cache of recent content SHA-256 hashes to prevent echo loops.
    private var recentHashes: [String] = []
    private let maxHashCacheSize = 50

    /// Callback when a new clipboard item is received from Android.
    public var onClipReceived: ((CloudSyncPayload) -> Void)?

    private init() {
        self.config = Self.loadConfig()
        setupSleepWakeObservers()
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

        status = .disconnected
    }

    public func reconnect() {
        disconnect()
        connect()
    }

    // MARK: - Send Clipboard to Cloud (Mac -> Android)

    /// Encrypts and transmits a new clipboard item copied on macOS to Android.
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

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8) else { return }

        // Try decoding envelope
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
