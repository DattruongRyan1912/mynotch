import Foundation

/// Translates with an engine that needs the user's key. It asks the service only when it is asked to translate, and
/// only the text it was given; a failure is reported and logged by kind, never by what the request held.
final class RemoteTranslationEngine: TranslationEngine {
    private let name: String
    /// Reads the key and settings when a translation starts, so a key typed in meanwhile is the one used.
    private let provider: () async throws -> any RemoteProvider
    private let transport: any HTTPTransport
    private let log: any TranslationLog

    init(
        name: String, provider: @escaping () async throws -> any RemoteProvider, transport: any HTTPTransport,
        log: any TranslationLog
    ) {
        self.name = name
        self.provider = provider
        self.transport = transport
        self.log = log
    }

    /// There is no language pack to download.
    func status(from source: Locale.Language, to target: Locale.Language) async -> PairStatus {
        .installed
    }

    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws(TranslationFailure) -> String {
        guard !text.allSatisfy(\.isWhitespace) else { return "" }
        do {
            let provider = try await provider()
            let request = try provider.request(for: text, from: source, to: target)
            let reply = try await transport.send(request)
            return try provider.translation(from: reply)
        } catch {
            throw failure(of: error)
        }
    }

    /// A request cancelled by a newer one is in flight at most once; there is nothing to cancel here.
    func invalidate() {}

    /// Anything unknown is reported as unreachable: an error's own description could quote the request, key included.
    private func failure(of error: any Error) -> TranslationFailure {
        let remote: RemoteFailure
        switch error {
        case is CancellationError:
            return .cancelled
        case let error as URLError where error.code == .cancelled:
            return .cancelled
        case let error as RemoteFailure:
            remote = error
        case let error as URLError:
            remote = RemoteFailure(error)
        default:
            remote = .unreachable
        }
        log.write("\(name) failed: \(remote.logDescription)", level: .error)
        return .failed(remote.message(for: name))
    }
}
