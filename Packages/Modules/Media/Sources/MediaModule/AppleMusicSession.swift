import Foundation

/// What identifies the user to Apple Music's web API: the web player's developer token, the user's own token and the
/// store the account belongs to (a two-letter country code such as "vn"). These are credentials: never logged or shown,
/// so printing one (a log line, a failed expectation, `dump`) leaves the tokens out.
nonisolated struct AppleMusicCredentials: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    var developerToken: String
    var userToken: String
    /// nil when the web page did not say; the client asks Apple then.
    var storefront: String?

    var description: String { "AppleMusicCredentials(tokens redacted, storefront: \(storefront ?? "nil"))" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: ["storefront": storefront as Any], displayStyle: .struct) }
}

/// Finds the credentials in what the sign-in window can see: the web player's MusicKit and its cookies.
nonisolated enum AppleMusicSessionReader {
    /// Runs in the page; answers JSON text, `{}` when MusicKit is not there yet.
    static let script = """
    (() => {
        try {
            const music = MusicKit.getInstance();
            return JSON.stringify({ developerToken: music.developerToken, musicUserToken: music.musicUserToken, storefrontId: music.storefrontId });
        } catch (error) {
            return JSON.stringify({});
        }
    })()
    """

    static let userTokenCookieName = "media-user-token"

    /// nil until both tokens are there. The user token is the script's, else the `media-user-token` cookie of
    /// music.apple.com.
    static func credentials(scriptResult: String?, cookies: [HTTPCookie]) -> AppleMusicCredentials? {
        guard let scriptResult,
              let object = (try? JSONSerialization.jsonObject(with: Data(scriptResult.utf8))) as? [String: Any],
              let developerToken = token(object["developerToken"]) else { return nil }
        let cookie = cookies.first { $0.name == userTokenCookieName && isMusicAppleCom($0.domain) }?.value
        guard let userToken = token(object["musicUserToken"]) ?? token(cookie) else { return nil }
        return AppleMusicCredentials(developerToken: developerToken, userToken: userToken, storefront: storefront(object["storefrontId"]))
    }

    /// The country code in lower case, nil for anything else (an old numeric store id, a path, nothing): the value goes
    /// into request paths.
    static func storefront(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              text.utf8.count == 2, text.utf8.allSatisfy({ (97...122).contains($0) }) else { return nil }
        return text
    }

    private static func token(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func isMusicAppleCom(_ domain: String) -> Bool {
        let host = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        return host == "music.apple.com" || host.hasSuffix(".music.apple.com")
    }
}
