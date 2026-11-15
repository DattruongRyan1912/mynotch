import Foundation

/// Everything the engines that need a key take from outside the module; tests replace it with fakes.
struct EngineSetup {
    var keys: any KeyStore = KeychainKeyStore()
    var transport: any HTTPTransport = URLSessionTransport()
    var log: any TranslationLog = OSTranslationLog()
}

/// The engines a request can go to: Apple's, which is always there, and the ones that need a key, built when chosen.
struct EngineSet {
    let apple: any TranslationEngine
    let remote: (EngineChoice) -> (any TranslationEngine)?

    func engine(for choice: EngineChoice) -> any TranslationEngine {
        remote(choice) ?? apple
    }
}

/// Builds the engines that need a key. Each reads the key from the Keychain and the other settings when a translation
/// starts, not before, so a Mac where nobody chose one never reads a key.
final class RemoteEngines {
    private let keys: any KeyStore
    private let transport: any HTTPTransport
    private let log: any TranslationLog
    private let config: () -> EngineConfig

    init(keys: any KeyStore, transport: any HTTPTransport, log: any TranslationLog, config: @escaping () -> EngineConfig) {
        self.keys = keys
        self.transport = transport
        self.log = log
        self.config = config
    }

    /// nil for Apple's, which needs no key.
    func engine(for choice: EngineChoice) -> (any TranslationEngine)? {
        guard let secret = choice.secret else { return nil }
        return RemoteTranslationEngine(
            name: choice.name, provider: { [self] in try await provider(for: choice, secret: secret) }, transport: transport, log: log
        )
    }

    private func provider(for choice: EngineChoice, secret: TranslationSecret) async throws -> any RemoteProvider {
        guard let key = await keys.savedKey(secret) else { throw RemoteFailure.notConfigured("key") }
        let config = config()
        switch choice {
        case .google: return GoogleProvider(key: key)
        case .microsoft: return MicrosoftProvider(key: key, region: config.microsoftRegion)
        case .openAI: return OpenAIProvider(key: key, baseURL: config.openAIBaseURL, model: config.openAIModel)
        case .apple: throw RemoteFailure.notConfigured("key")
        }
    }
}
