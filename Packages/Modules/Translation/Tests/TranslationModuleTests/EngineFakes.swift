import Foundation
import Testing
import os
@testable import TranslationModule

/// Stands in for the Keychain's key store: values live in this object only, so no test ever reads or writes the real one.
nonisolated final class FakeKeyStore: KeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [TranslationSecret: String] = [:]
    private var saves = 0
    private var failing = false

    init(_ values: [TranslationSecret: String] = [:]) {
        stored = values
    }

    var values: [TranslationSecret: String] { lock.withLock { stored } }
    var saveCount: Int { lock.withLock { saves } }
    /// Makes every save fail, like a locked or unavailable Keychain.
    var failsToSave: Bool {
        get { lock.withLock { failing } }
        set { lock.withLock { failing = newValue } }
    }

    func load(_ secret: TranslationSecret) -> String? {
        lock.withLock { stored[secret] }
    }

    func save(_ value: String, for secret: TranslationSecret) -> Bool {
        lock.withLock {
            saves += 1
            guard !failing else { return false }
            stored[secret] = value
            return true
        }
    }

    func remove(_ secret: TranslationSecret) {
        lock.withLock { stored[secret] = nil }
    }
}

/// Stands in for the network: tests set what each request gets and read what was sent, so none reaches a server.
final class FakeTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    /// What every request gets; until a test sets it, requests fail like a dead connection.
    var handler: (URLRequest) async throws -> HTTPReply = { _ in throw URLError(.notConnectedToInternet) }
    /// When true, requests wait for `release()` before the handler answers.
    var holds = false
    private var held: CheckedContinuation<Void, Never>?

    var waiting: Bool { held != nil }

    func send(_ request: URLRequest) async throws -> HTTPReply {
        requests.append(request)
        if holds { await withCheckedContinuation { held = $0 } }
        try Task.checkCancellation()
        return try await handler(request)
    }

    func reply(_ reply: HTTPReply) {
        handler = { _ in reply }
    }

    func release() {
        held?.resume()
        held = nil
    }

    /// The JSON the last request carried.
    func lastBody() throws -> Any {
        let body = try #require(requests.last?.httpBody)
        return try JSONSerialization.jsonObject(with: body)
    }
}

/// What the translation log was asked to write, so tests can read it; nothing reaches the unified log.
nonisolated final class FakeTranslationLog: TranslationLog, @unchecked Sendable {
    private let lock = NSLock()
    private var written: [(message: String, level: OSLogType)] = []

    var lines: [String] { lock.withLock { written.map(\.message) } }
    var levels: [OSLogType] { lock.withLock { written.map(\.level) } }

    func write(_ message: String, level: OSLogType) {
        lock.withLock { written.append((message, level)) }
    }
}

/// An in-memory Keychain that answers like the real one: an unknown item is `errSecItemNotFound`, adding a known one is
/// `errSecDuplicateItem`. It keeps every item it was asked to add, so tests can read the attributes the real one would get.
nonisolated final class FakeKeychain: KeychainAccess, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    private var attributes: [[String: Any]] = []
    private var adds = 0
    private var updates = 0
    private var addStatus: OSStatus = errSecSuccess

    var addCount: Int { lock.withLock { adds } }
    var updateCount: Int { lock.withLock { updates } }
    var added: [[String: Any]] { lock.withLock { attributes } }
    var stored: [String: Data] { lock.withLock { items } }
    var failsToAdd: OSStatus {
        get { lock.withLock { addStatus } }
        set { lock.withLock { addStatus = newValue } }
    }

    func copy(_ query: [CFString: Any]) -> (status: OSStatus, data: Data?) {
        lock.withLock {
            guard let data = items[Self.id(query)] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, data)
        }
    }

    func add(_ item: [CFString: Any]) -> OSStatus {
        lock.withLock {
            adds += 1
            guard addStatus == errSecSuccess else { return addStatus }
            guard items[Self.id(item)] == nil else { return errSecDuplicateItem }
            items[Self.id(item)] = item[kSecValueData] as? Data
            attributes.append(Dictionary(uniqueKeysWithValues: item.map { ($0.key as String, $0.value) }))
            return errSecSuccess
        }
    }

    func update(_ query: [CFString: Any], with attributes: [CFString: Any]) -> OSStatus {
        lock.withLock {
            updates += 1
            guard items[Self.id(query)] != nil else { return errSecItemNotFound }
            items[Self.id(query)] = attributes[kSecValueData] as? Data
            return errSecSuccess
        }
    }

    func delete(_ query: [CFString: Any]) -> OSStatus {
        lock.withLock { items.removeValue(forKey: Self.id(query)) == nil ? errSecItemNotFound : errSecSuccess }
    }

    private static func id(_ query: [CFString: Any]) -> String {
        "\(query[kSecAttrService] as? String ?? "")|\(query[kSecAttrAccount] as? String ?? "")"
    }
}

/// Like `eventually`, for work that goes through another thread first (a Keychain read, the dictionary): yielding to the
/// main actor cannot wait for that, so this polls, for up to ten seconds, which only a machine under heavy load needs.
func eventuallyAfterWaiting(_ condition: () -> Bool) async {
    for _ in 0..<2000 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
}
