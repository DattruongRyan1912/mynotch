import Foundation
import Observation

/// What the Settings rows of the engines do: keep and forget keys, and run the "Kiểm tra" request. It never holds a key
/// longer than a call, and never gives one back.
@Observable
final class EngineSettingsModel {
    enum Check: Equatable {
        case running
        case ok
        case failed(String)
    }

    /// Engines whose key is saved; filled in by `refresh`.
    private(set) var savedKeys: Set<EngineChoice> = []
    /// `refresh` has answered at least once; until then the rows do not claim a key is missing.
    private(set) var hasLoaded = false
    /// The latest "Kiểm tra" result of each engine, until its key changes.
    private(set) var checks: [EngineChoice: Check] = [:]
    /// Why the last key could not be saved or removed.
    private(set) var keyError: String?

    private let keys: any KeyStore
    private let engines: RemoteEngines
    private let log: any TranslationLog

    init(keys: any KeyStore, engines: RemoteEngines, log: any TranslationLog) {
        self.keys = keys
        self.engines = engines
        self.log = log
    }

    /// Apple's engine needs no key, so it always has one.
    func hasKey(_ choice: EngineChoice) -> Bool {
        choice.secret == nil || savedKeys.contains(choice)
    }

    /// Looks up which keys are saved, without showing any.
    func refresh() async {
        var saved = Set<EngineChoice>()
        for choice in EngineChoice.allCases {
            if let secret = choice.secret, await keys.hasSavedKey(secret) { saved.insert(choice) }
        }
        savedKeys = saved
        hasLoaded = true
    }

    /// Keeps the key, trimmed. False for a blank key, an engine without keys, or a Keychain that refused.
    func save(_ key: String, for choice: EngineChoice) async -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let secret = choice.secret, !key.isEmpty else { return false }
        guard await keys.keep(key, as: secret) else {
            keyError = "Không lưu được key vào Keychain"
            log.write("Could not save the \(choice.name) key to the Keychain", level: .error)
            return false
        }
        keyError = nil
        savedKeys.insert(choice)
        checks[choice] = nil
        return true
    }

    /// Deletes the key. If the Keychain refuses, the key is still there, so it stays marked as saved and the error says
    /// so: "Xoá key" never claims what did not happen.
    @discardableResult
    func remove(_ choice: EngineChoice) async -> Bool {
        guard let secret = choice.secret else { return false }
        guard await keys.discard(secret) else {
            keyError = "Không xoá được key khỏi Keychain"
            log.write("Could not remove the \(choice.name) key from the Keychain", level: .error)
            return false
        }
        keyError = nil
        savedKeys.remove(choice)
        checks[choice] = nil
        return true
    }

    /// One real request with a fixed word, never the user's text, to see that the key and settings work.
    func test(_ choice: EngineChoice) async {
        guard let engine = engines.engine(for: choice), checks[choice] != .running else { return }
        checks[choice] = .running
        do throws(TranslationFailure) {
            _ = try await engine.translate("Hello", from: Locale.Language(identifier: "en"), to: Locale.Language(identifier: "vi"))
            checks[choice] = .ok
        } catch {
            if case .failed(let message) = error { checks[choice] = .failed(message) } else { checks[choice] = nil }
        }
    }
}
