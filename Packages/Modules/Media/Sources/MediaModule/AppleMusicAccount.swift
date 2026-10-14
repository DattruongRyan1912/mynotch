import Foundation
import Observation

/// Whether MyNotch may use the user's Apple Music sign-in, and the sign-in itself, kept in a `TokenStore`.
/// Tokens never leave this type except as `credentials`, for the requests that need them.
@Observable
final class AppleMusicAccount {
    nonisolated enum Status: Equatable, Sendable {
        case notConnected
        case connected(storefront: String)
        /// Apple rejected the tokens twice in a row: nothing is asked until the user signs in again.
        case needsReauth

        var text: String {
            switch self {
            case .notConnected: "Chưa kết nối"
            case .connected(let storefront): "Đã kết nối (\(storefront))"
            case .needsReauth: "Cần đăng nhập lại"
            }
        }

        /// Only a connected account is asked for lyrics.
        var isConnected: Bool {
            if case .connected = self { true } else { false }
        }
    }

    static let keychainProblem = "Không lưu được token vào Keychain của máy."

    private(set) var status = Status.notConnected
    /// Why the last attempt to connect failed, for the Settings row; nil after a success or a disconnect.
    var problem: String?

    @ObservationIgnored private let tokens: any TokenStore
    @ObservationIgnored private var isLoaded = false

    init(tokens: any TokenStore) {
        self.tokens = tokens
    }

    /// Reads an earlier sign-in. Not in `init`, so creating the module touches no Keychain; only the first call reads,
    /// so it can never undo a sign-in the user has just made or a "needs sign-in" found since.
    func load() {
        guard !isLoaded else { return }
        isLoaded = true
        if let storefront = credentials?.storefront { status = .connected(storefront: storefront) }
    }

    /// Everything the stored sign-in holds; nil unless all of it is there.
    var credentials: AppleMusicCredentials? {
        guard let developerToken = tokens.load(.developerToken), let userToken = tokens.load(.mediaUserToken),
              let storefront = AppleMusicSessionReader.storefront(tokens.load(.storefront)) else { return nil }
        return AppleMusicCredentials(developerToken: developerToken, userToken: userToken, storefront: storefront)
    }

    /// Stores a sign-in, all of it or nothing. False without a storefront, or when the store refuses (then `problem` says so).
    func connect(_ credentials: AppleMusicCredentials) -> Bool {
        isLoaded = true
        guard let storefront = credentials.storefront else { return false }
        let saved = tokens.save(credentials.developerToken, for: .developerToken)
            && tokens.save(credentials.userToken, for: .mediaUserToken)
            && tokens.save(storefront, for: .storefront)
        guard saved else {
            removeEverything()
            problem = Self.keychainProblem
            return false
        }
        status = .connected(storefront: storefront)
        problem = nil
        return true
    }

    /// The web player's developer token, renewed. A store that cannot keep it only costs another renewal next time.
    func replaceDeveloperToken(_ token: String) {
        _ = tokens.save(token, for: .developerToken)
    }

    /// The storefront the account itself reports (`/v1/me/storefront`), which is where its lyrics are: kept in place of the
    /// one MusicKit gave. Nothing happens for an account that is not connected, or when the store refuses.
    func replaceStorefront(_ storefront: String) {
        guard status != .notConnected, tokens.save(storefront, for: .storefront) else { return }
        if status.isConnected { status = .connected(storefront: storefront) }
    }

    func markNeedsReauth() {
        if status.isConnected { status = .needsReauth }
    }

    func disconnect() {
        isLoaded = true
        removeEverything()
        problem = nil
    }

    private func removeEverything() {
        for secret in AppleMusicSecret.allCases { tokens.remove(secret) }
        status = .notConnected
    }
}
