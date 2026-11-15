import Foundation
import Testing
@testable import ClipboardModule

/// What looks like a password or a key and is therefore never handed to an agent, whatever the flag of the item says. Every
/// secret here is made up, and the ones with a famous prefix are put together at run time, so no scanner reads this file as a leak.
@Suite struct ClipboardMCPSecretFilterTests {
    func hides(_ text: String) -> Bool {
        ClipboardMCPSecretFilter.looksLikeSecret(text)
    }

    /// Looks random: 38 different characters, no separator, letters and digits.
    let random = "7Hq2LkP9xZc4VbN8mR1sT6yUeW3aDfG5jKo0iB"
    let random64 = "aB3dE5gH7jK9mN1pQ3sT5vW7yZ9bC2eF4hJ6kM8nP0qR2tU4wX6zA8cD0fG2iL4"

    // MARK: API keys and tokens

    @Test func anOpenAIOrAnthropicKeyIsHidden() {
        for text in [
            "sk" + "-" + random + random,
            "sk" + "-ant-api03-" + random + "AA",
            "sk" + "-proj-" + random + "_" + random,
            "OPENAI_KEY is sk" + "-" + random + random + " ok",
        ] {
            #expect(hides(text), "\(text)")
        }
    }

    @Test func aWordThatMerelyContainsSkDashIsNotAKey() {
        #expect(!hides("desk-lamp-assembly-instructions-for-the-new-office"))
        #expect(!hides("sk-learn is a library"))
        #expect(!hides("the task-based approach to hyphenated-compound-words-in-a-sentence"))
        #expect(!hides("sk-short"))
    }

    @Test func aGitHubTokenIsHidden() {
        for prefix in ["ghp", "gho", "ghu", "ghs", "ghr"] {
            #expect(hides(prefix + "_" + String(random.prefix(36))), "\(prefix)")
        }
        #expect(hides("github" + "_pat_" + random + random))
        #expect(!hides("ghp_"))
        #expect(!hides("ghp_short"))
    }

    @Test func aSlackTokenOrWebhookIsHidden() {
        for kind in ["a", "b", "p", "r", "o", "s"] {
            #expect(hides("xox" + kind + "-1234567890-0987654321-" + String(random.prefix(24))), "\(kind)")
        }
        #expect(hides("https://hooks." + "slack.com/services/T01234567/B01234567/" + String(random.prefix(24))))
        #expect(!hides("xoxo, see you soon"))
    }

    @Test func anAWSAccessKeyIsHidden() {
        #expect(hides("AK" + "IA" + "IOSFODNN7EXAMPLE"))
        #expect(hides("AS" + "IA" + "IOSFODNN7EXAMPLE"))
        #expect(hides("aws_access_key_id=AK" + "IA" + "IOSFODNN7EXAMPLE"))
        #expect(!hides("AKIA is the start of it"))
        #expect(!hides("MAKIAIOSFODNN7EXAMPLEX"))
    }

    @Test func aGoogleAPIKeyIsHidden() {
        #expect(hides("AI" + "za" + String(random.prefix(35))))
        #expect(!hides("AIzaShort"))
    }

    @Test func aGitLabTokenIsHidden() {
        #expect(hides("gl" + "pat-" + String(random.prefix(26))))
        #expect(!hides("glpat- is the prefix"))
    }

    @Test func aStripeKeyIsHidden() {
        #expect(hides("sk" + "_live_" + String(random.prefix(26))))
        #expect(hides("rk" + "_live_" + String(random.prefix(26))))
        #expect(hides("sk" + "_test_" + String(random.prefix(26))))
        #expect(!hides("sk_live_ prefix"))
    }

    @Test func aJWTIsHidden() {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" + "." + "eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0" + "." + "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        #expect(hides(jwt))
        #expect(hides("token is " + jwt + " now"))
        #expect(!hides("eyJ is how base64 JSON begins"))
        #expect(!hides("version 1.2.3 of the app, build 4.5.6"))
    }

    @Test func aBearerTokenOrAuthorizationHeaderIsHidden() {
        #expect(hides("Bearer " + String(random.prefix(30))))
        #expect(hides("curl -H \"Authorization: Bearer " + String(random.prefix(30)) + "\" https://example.com"))
        #expect(hides("Authorization: Basic dXNlcjpwYXNzd29yZA=="))
        #expect(hides("authorization: token " + String(random.prefix(20))))
        #expect(!hides("Bearer of bad news and a few other things"))
        #expect(!hides("Authorization: required for all access to this room"))
    }

    // MARK: Keys in a file

    @Test func aPEMBlockOfAnyTypeIsHidden() {
        for type in ["RSA PRIVATE KEY", "PRIVATE KEY", "EC PRIVATE KEY", "OPENSSH PRIVATE KEY", "ENCRYPTED PRIVATE KEY", "PGP PRIVATE KEY BLOCK", "CERTIFICATE", "PUBLIC KEY"] {
            #expect(hides("-----BEGIN \(type)-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASC\n-----END \(type)-----"), "\(type)")
        }
        #expect(hides("some text\n-----BEGIN PRIVATE KEY-----"))
        #expect(!hides("-----BEGIN is how a PEM begins"))
    }

    // MARK: High entropy

    @Test func aLongRandomLookingStringIsHidden() {
        #expect(hides(random))
        #expect(hides(random64))
        #expect(hides("the key is \(random) and that is all"))
        #expect(hides("{\"value\":\"\(random)\"}"))
        #expect(hides("\"\(random64)\""))
        #expect(hides("export SOMETHING=\(random)"))
        #expect(hides("Zm9vYmFyYmF6cXV4Zm9vYmFyYmF6cXV4Zm9v" + "QUJDRDEyMzQ1Ng=="))
    }

    @Test func aStringJustUnderTheLengthIsLeftAlone() {
        #expect(!hides(String(random.prefix(31))))
    }

    @Test func aLongPathSlugIdentifierOrHashIsNotAKey() {
        for text in [
            "/Users/ryantruong/Project/MyNotch/Packages/Modules/Clipboard/Sources/ClipboardModule/ClipboardModule.swift",
            "Packages/Modules/Clipboard/Sources/ClipboardMCPKit/MCPSession.swift",
            "com.apple.security.personal-information.calendars",
            "NSCalendarsFullAccessUsageDescription",
            "kubernetes-dashboard-metrics-scraper-5d59dccf9b-x7k2m",
            "IMG_20261015_173045_HDR_final_version_2.jpeg",
            "how-to-build-a-secure-system-with-rust-5f3a9c2b1d",
            "550e8400-e29b-41d4-a716-446655440000",
            "a94a8fe5ccb19ba61c4c0873d391e987982fbbd3",
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        ] {
            #expect(!hides(text), "\(text)")
        }
    }

    @Test func anOrdinaryLinkPassesEvenWithAnOpaqueQuery() {
        for text in [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://example.com/blog/how-to-build-a-secure-system-with-rust-5f3a9c2b1d",
            "https://www.google.com/search?q=how+to+bake+bread&oq=how+to+bake+bread&sourceid=chrome&ie=UTF-8",
            "https://github.com/apple/swift/pull/12345",
            "http://localhost:3000/api/users?id=42&sort=name",
            "https://example.com:8443/a/b/c",
            "https://example.com/share?id=" + random + "&utm_source=newsletter",
            "https://example.com/#section-" + random,
        ] {
            #expect(!hides(text), "\(text)")
        }
    }

    @Test func aLongOpaqueSegmentInThePathOfALinkIsAKey() {
        #expect(hides("https://example.com/download/" + random64))
        #expect(hides("https://example.com/d/" + random + "/view"))
    }

    // MARK: Credentials in a link

    @Test func aQueryParameterThatCarriesACredentialIsHidden() {
        for text in [
            "https://api.example.com/v1/data?token=abcd1234efgh5678",
            "https://api.example.com/v1/data?api_key=abcd1234efgh5678",
            "https://api.example.com/v1/data?x=1&key=abcd1234efgh5678",
            "https://api.example.com/v1/data?apikey=abcd1234",
            "https://example.com/login?user=ann&password=hunter22",
            "https://example.com/cb#access_token=abcd1234efgh5678&state=1",
            "https://example.com/x?client_secret=abcd1234efgh&a=b",
            "https://example.com/x?sig=abcd1234efgh",
        ] {
            #expect(hides(text), "\(text)")
        }
    }

    @Test func aQueryParameterThatHasANameLikeAKeyButNoValueOrAShortOneIsLeftAlone() {
        #expect(!hides("https://example.com/search?key=1&token="))
        #expect(!hides("https://example.com/x?keyboard=qwerty&monkey=banana&tokenizer=basic"))
    }

    @Test func aConnectionStringWithCredentialsIsHidden() {
        for text in [
            "postgres://admin:s3cr3t@db.example.com:5432/app",
            "mongodb+srv://user:pass1234@cluster0.example.net/db",
            "redis://:password1@host:6379",
            "https://user:pw12@example.com/path",
            "amqp://guest:guest@localhost:5672/",
            "DATABASE_URL=mysql://root:toor@127.0.0.1/db",
        ] {
            #expect(hides(text), "\(text)")
        }
    }

    @Test func aConnectionStringWithoutCredentialsIsLeftAlone() {
        for text in [
            "postgres://db.example.com:5432/app", "https://example.com:8443/a", "redis://localhost:6379",
            "mailto:ann@example.com", "write to ann@example.com", "git@github.com:apple/swift.git", "ssh://git@github.com/apple/swift.git",
        ] {
            #expect(!hides(text), "\(text)")
        }
    }

    // MARK: Password lines

    @Test func aLineThatNamesAPasswordOrKeyAndGivesAValueIsHidden() {
        for text in [
            "password: hunter2!", "PASSWORD=Sup3rS3cret", "pwd = abcd1234", "passwd:abcd1234", "Password : abcd1234",
            "mật khẩu: abc12345", "Mật khẩu = abc12345", "mat khau: 123456", "MẬT KHẨU: abc12345",
            "mã bí mật: 998877", "ma bi mat = 998877", "mã OTP: 482913", "OTP: 482913",
            "secret: s3cr3tv4lue", "api_key = abc123xyz", "API-KEY: zzzz9999", "apikey=zzzz9999", "token=abcdef", "access_token: abcdef12",
            "export DB_PASSWORD=abc12345", "{\"password\": \"hunter22\"}", "'password': 'hunter22'", "client_secret=abcdef12",
            "wifi\nPassword: sunshine99\nenjoy",
        ] {
            #expect(hides(text), "\(text)")
        }
    }

    @Test func aMentionOfAPasswordWithoutAValueIsLeftAlone() {
        for text in [
            "Tôi quên mật khẩu rồi, phải đặt lại thôi.", "Mật khẩu wifi nhà bạn là gì nhỉ?", "Please reset your password before you log in.",
            "The token of appreciation was a handwritten note; the secret to good bread is patience.",
            "password", "secret:", "token: ", "the password is required", "Password:", "password: x",
        ] {
            #expect(!hides(text), "\(text)")
        }
    }

    @Test func aTypeAnnotationOrAPlaceholderIsNotAPassword() {
        for text in [
            "struct Login { var username: String; var password: String }", "let token: Int", "password: required", "password: string",
            "secret: Bool", "var apiKey: Optional<String>",
        ] {
            #expect(!hides(text), "\(text)")
        }
    }

    @Test func comparisonsAndScopesAreNotAssignments() {
        #expect(!hides("if token == nil { return }"))
        #expect(!hides("Foo::password::Bar"))
        #expect(!hides("tokenCount = 5"))
        #expect(!hides("hotpot: delicious and spicy"))
    }

    // MARK: Ordinary things

    @Test func ordinaryProseColoursAndCodeAreNotHidden() {
        for text in [
            "Hôm nay tôi đi chợ mua rau, cá và thịt cho bữa tối cả nhà. Mai gặp nhau lúc 9 giờ sáng ở quán cà phê gần công viên nhé.",
            "Meeting moved to Thursday at 10:30, room B2. Please bring the signed contract and the updated budget spreadsheet.",
            "#FF8800", "#ff880080", "rgb(255, 136, 0)", "hsl(30, 100%, 50%)",
            "func fetch(items: [Item]) async throws -> Data {\n    let count = items.count\n    return try await load(count)\n}",
            "{\"name\":\"MyNotch\",\"version\":\"1.0.0\",\"description\":\"A notch utility for macOS\"}",
            "SELECT id, name FROM users WHERE created_at > '2026-01-01' ORDER BY name LIMIT 10;",
            "ryan@example.com", "0901 234 567", "ghp", "-----", "",
        ] {
            #expect(!hides(text), "\(text)")
        }
    }

    @Test func onlyTheStartOfAVeryLongTextIsLookedAt() {
        // What an agent could be given or search is at most this much of a text, and a text of a few megabytes is not read twice.
        let tail = String(repeating: "x", count: ClipboardMCPSecretFilter.maxScannedCharacters) + " password: hunter2!"
        #expect(!hides(tail))
        #expect(hides("password: hunter2! " + String(repeating: "x", count: ClipboardMCPSecretFilter.maxScannedCharacters)))
    }

    @Test func longRunsOfOneKindOfCharacterAreReadWithoutBacktrackingTrouble() {
        // Each of these is the start of some pattern, repeated to the limit; a pattern that tried it again from every letter
        // would take minutes, and the whole suite would show it.
        let limit = ClipboardMCPSecretFilter.maxScannedCharacters
        for text in [
            String(repeating: "a", count: limit), String(repeating: "a:", count: limit / 2), String(repeating: "a.", count: limit / 2),
            "http://" + String(repeating: "a", count: limit), "http://" + String(repeating: "a:", count: limit / 2),
            "sk-" + String(repeating: "a", count: limit), String(repeating: "sk-", count: limit / 3), String(repeating: "eyJ", count: limit / 3),
            String(repeating: "password", count: limit / 8), String(repeating: "password:", count: limit / 9), String(repeating: "-", count: limit),
            String(repeating: "?token=", count: limit / 7), String(repeating: "bearer ", count: limit / 7), String(repeating: "=", count: limit),
            String(repeating: "A", count: limit - 2) + "1a", String(repeating: "a-", count: limit / 2) + "1",
            String(repeating: "http://x/a ", count: limit / 11), String(repeating: "key=1&", count: limit / 6), String(repeating: "token: ", count: limit / 7),
            String(repeating: "AKIA", count: limit / 4), String(repeating: "-----BEGIN ", count: limit / 11), String(repeating: "a1B2c3D4-", count: limit / 9),
            String(repeating: "ab+://", count: limit / 6), String(repeating: "u:p@", count: limit / 4), String(repeating: "authorization: bearer ", count: limit / 22),
            String(repeating: "eyJabcdefgh.", count: limit / 12), "http://x.com/" + String(repeating: "a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6/", count: limit / 33),
        ] {
            _ = hides(text)
        }
    }

    @Test func aHugeTextIsScannedQuickly() {
        let text = String(repeating: "lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 40_000)
        #expect(!hides(text))
    }

    // MARK: Items

    func item(_ content: ClipboardContent, sensitive: Bool? = nil, hash: String = UUID().uuidString) -> ClipboardItem {
        ClipboardItem(id: UUID(), content: content, contentHash: hash, copiedAt: .now, sourceBundleID: nil, sourceAppName: nil, sensitive: sensitive)
    }

    @Test func theTextOfEveryKindOfItemIsChecked() {
        let secretLink = URL(string: "https://example.com/x?token=abcd1234efgh")!
        #expect(ClipboardMCPSecretFilter.hides(item(.text("password: hunter2!"))))
        #expect(ClipboardMCPSecretFilter.hides(item(.richText(plain: "password: hunter2!", rtf: Data()))))
        #expect(ClipboardMCPSecretFilter.hides(item(.link(secretLink))))
        #expect(ClipboardMCPSecretFilter.hides(item(.color(hex: "#FF8800", original: "password: hunter2!"))))
        #expect(!ClipboardMCPSecretFilter.hides(item(.text("hello world"))))
        #expect(!ClipboardMCPSecretFilter.hides(item(.link(URL(string: "https://example.com/")!))))
        #expect(!ClipboardMCPSecretFilter.hides(item(.color(hex: "#FF8800"))))
    }

    @Test func aFileIsCheckedByItsNameAndNotByTheFoldersAbove() {
        let long = "/Users/someone/Library/Mobile Documents/com~apple~CloudDocs/Work/Clients/AcmeCorporation/2026/Invoices/INV-0001.pdf"
        #expect(!ClipboardMCPSecretFilter.hides(item(.files([URL(filePath: long)]))))
        #expect(ClipboardMCPSecretFilter.hides(item(.files([URL(filePath: "/tmp/" + random + ".txt")]))))
        #expect(ClipboardMCPSecretFilter.hides(item(.files([URL(filePath: "/tmp/ok.txt"), URL(filePath: "/tmp/password=abc12345.txt")]))))
    }

    @Test func anImageHasNoTextToBeChecked() {
        #expect(!ClipboardMCPSecretFilter.hides(item(ClipboardModuleTests.image("a"))))
    }

    @Test func theCacheGivesTheSameAnswerAndLooksAgainWhenTheContentChanges() {
        let cache = ClipboardMCPSecretFilter.Cache()
        var changing = item(.text("hello"), hash: "h1")
        #expect(!cache.hides(changing))
        #expect(cache.verdictCount == 1)
        #expect(!cache.hides(changing))
        #expect(cache.scanCount == 1)
        changing.content = .text("password: hunter2!")
        // The same hash is the same content: the old verdict stands until the hash changes, as the history's rule says.
        #expect(!cache.hides(changing))
        changing.contentHash = "h2"
        #expect(cache.hides(changing))
        #expect(cache.scanCount == 2)
    }

    @Test func theCacheForgetsItemsThatLeftTheHistory() {
        let cache = ClipboardMCPSecretFilter.Cache()
        let items = (0..<10).map { item(.text("n\($0)")) }
        for item in items { _ = cache.hides(item) }
        #expect(cache.verdictCount == 10)
        cache.keepOnly(Set(items.prefix(3).map(\.id)))
        #expect(cache.verdictCount == 3)
    }
}
