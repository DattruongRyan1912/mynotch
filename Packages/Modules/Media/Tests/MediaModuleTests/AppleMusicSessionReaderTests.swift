import Foundation
import Testing
@testable import MediaModule

/// Fake tokens only; nothing here is a real credential.
@Suite struct AppleMusicSessionReaderTests {
    func json(developer: Any? = "dev-token-fake", user: Any? = "user-token-fake", storefront: Any? = "vn") -> String {
        var object: [String: Any] = [:]
        if let developer { object["developerToken"] = developer }
        if let user { object["musicUserToken"] = user }
        if let storefront { object["storefrontId"] = storefront }
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    func cookie(_ name: String = "media-user-token", domain: String = ".music.apple.com", value: String = "cookie-token-fake") -> HTTPCookie {
        HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: "/"])!
    }

    // MARK: script result

    @Test func allThreeFromTheScript() {
        let credentials = AppleMusicSessionReader.credentials(scriptResult: json(), cookies: [])
        #expect(credentials == AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: "vn"))
    }

    @Test func valuesAreTrimmed() {
        let credentials = AppleMusicSessionReader.credentials(scriptResult: json(developer: " dev-token-fake\n", user: "\tuser-token-fake ", storefront: " VN "), cookies: [])
        #expect(credentials == AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: "vn"))
    }

    @Test func withoutTheStorefrontItIsNilForTheCallerToFetch() {
        #expect(AppleMusicSessionReader.credentials(scriptResult: json(storefront: nil), cookies: [])?.storefront == nil)
    }

    @Test(arguments: ["", " ", "v", "vnn", "v1", "v n", "143441-2,29", "../x", "vn/../../me"])
    func aStorefrontThatIsNotACountryCodeIsDropped(storefront: String) {
        let credentials = AppleMusicSessionReader.credentials(scriptResult: json(storefront: storefront), cookies: [])
        #expect(credentials?.developerToken == "dev-token-fake")
        #expect(credentials?.storefront == nil)
    }

    @Test func aStorefrontThatIsNotAStringIsDropped() {
        #expect(AppleMusicSessionReader.credentials(scriptResult: json(storefront: 143_441), cookies: [])?.storefront == nil)
    }

    // MARK: the cookie fallback

    @Test func theCookieStandsInForAMissingUserToken() {
        let credentials = AppleMusicSessionReader.credentials(scriptResult: json(user: nil), cookies: [cookie()])
        #expect(credentials?.userToken == "cookie-token-fake")
        #expect(credentials?.developerToken == "dev-token-fake")
    }

    @Test func theCookieStandsInForAnEmptyUserToken() {
        for empty in [NSNull(), "", "  "] as [Any] {
            #expect(AppleMusicSessionReader.credentials(scriptResult: json(user: empty), cookies: [cookie()])?.userToken == "cookie-token-fake")
        }
    }

    @Test func theScriptsUserTokenWinsOverTheCookie() {
        #expect(AppleMusicSessionReader.credentials(scriptResult: json(), cookies: [cookie()])?.userToken == "user-token-fake")
    }

    @Test(arguments: [".music.apple.com", "music.apple.com", "www.music.apple.com"])
    func cookiesOfMusicAppleCom(domain: String) {
        #expect(AppleMusicSessionReader.credentials(scriptResult: json(user: nil), cookies: [cookie(domain: domain)])?.userToken == "cookie-token-fake")
    }

    @Test(arguments: [".apple.com", "evil-music.apple.com", "music.apple.com.evil.example", ".example.com"])
    func cookiesOfOtherDomainsAreIgnored(domain: String) {
        #expect(AppleMusicSessionReader.credentials(scriptResult: json(user: nil), cookies: [cookie(domain: domain, value: "other-token-fake")]) == nil)
    }

    @Test func onlyTheMediaUserTokenCookieCounts() {
        #expect(AppleMusicSessionReader.credentials(scriptResult: json(user: nil), cookies: [cookie("session-id", value: "x"), cookie("Media-User-Token", value: "y")]) == nil)
    }

    @Test func anEmptyCookieIsNothing() {
        #expect(AppleMusicSessionReader.credentials(scriptResult: json(user: nil), cookies: [cookie(value: " ")]) == nil)
    }

    // MARK: not signed in yet

    @Test func withoutADeveloperTokenThereIsNothing() {
        #expect(AppleMusicSessionReader.credentials(scriptResult: json(developer: nil), cookies: [cookie()]) == nil)
        #expect(AppleMusicSessionReader.credentials(scriptResult: json(developer: ""), cookies: [cookie()]) == nil)
        #expect(AppleMusicSessionReader.credentials(scriptResult: json(developer: 5), cookies: [cookie()]) == nil)
    }

    @Test func withoutAnyUserTokenThereIsNothing() {
        #expect(AppleMusicSessionReader.credentials(scriptResult: json(user: nil), cookies: []) == nil)
        #expect(AppleMusicSessionReader.credentials(scriptResult: json(user: ""), cookies: []) == nil)
    }

    @Test(arguments: [nil, "", "{}", "null", "[]", "not json", "\"text\"", "{\"developerToken\":"] as [String?])
    func aScriptThatFailedOrAnsweredNothingIsNothing(result: String?) {
        #expect(AppleMusicSessionReader.credentials(scriptResult: result, cookies: []) == nil)
        #expect(AppleMusicSessionReader.credentials(scriptResult: result, cookies: [cookie()]) == nil)
    }

    @Test func theScriptReadsMusicKitAndNeverThrows() {
        let script = AppleMusicSessionReader.script
        for name in ["MusicKit.getInstance()", "developerToken", "musicUserToken", "storefrontId", "JSON.stringify", "try", "catch"] {
            #expect(script.contains(name), "\(name)")
        }
    }

    // MARK: no printing of tokens

    @Test func credentialsNeverPrintTheirTokens() {
        let credentials = AppleMusicCredentials(developerToken: "dev-token-fake", userToken: "user-token-fake", storefront: "vn")
        var dumped = ""
        dump(credentials, to: &dumped)
        let texts = [
            String(describing: credentials), String(reflecting: credentials), "\(credentials)", dumped,
            "\([credentials])", String(describing: Optional(credentials)), "\(Mirror(reflecting: credentials).children.map { "\($0.label ?? "") \($0.value)" })",
        ]
        for text in texts {
            #expect(!text.contains("dev-token-fake"))
            #expect(!text.contains("user-token-fake"))
        }
        #expect(String(describing: credentials).contains("vn"))
    }
}
