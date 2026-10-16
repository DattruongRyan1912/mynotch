import Testing
@testable import PortsModule

@Suite struct SecretMaskTests {
    nonisolated struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let arguments: [String]
        /// The line a row would show; the same as the input line when nothing is a secret.
        let shown: String
        var testDescription: String { name }
    }


    /// What is hidden. The value goes, the flag or variable name stays.
    nonisolated static let hidden: [Case] = [
        Case(name: "--password=value", arguments: ["node", "app.js", "--password=hunter2"], shown: "node app.js --password=••••"),
        Case(name: "--token value", arguments: ["app", "--token", "abc123"], shown: "app --token ••••"),
        Case(name: "--token=value", arguments: ["app", "--token=abc123", "--port=3000"], shown: "app --token=•••• --port=3000"),
        Case(name: "mysql -pSECRET", arguments: ["/usr/local/bin/mysql", "-u", "root", "-phunter2"], shown: "mysql -u root -p••••"),
        Case(name: "mariadb -pSECRET", arguments: ["mariadb", "-pSecret"], shown: "mariadb -p••••"),
        Case(name: "PASSWORD=value in an env line", arguments: ["env", "PASSWORD=hunter2", "node", "a.js"], shown: "env PASSWORD=•••• node a.js"),
        Case(name: "docker -e DB_PASSWORD=value", arguments: ["docker", "run", "-e", "DB_PASSWORD=x", "img"], shown: "docker run -e DB_PASSWORD=•••• img"),
        Case(name: "URL with user:pass@", arguments: ["node", "a.js", "--db=postgres://admin:s3cret@localhost:5432/app"], shown: "node a.js --db=postgres://admin:••••@localhost:5432/app"),
        Case(name: "URL as its own argument", arguments: ["app", "redis://:hunter2@cache:6379/0"], shown: "app redis://:••••@cache:6379/0"),
        Case(name: "--api-key value", arguments: ["app", "--api-key", "k-123"], shown: "app --api-key ••••"),
        Case(name: "--api_key=value", arguments: ["app", "--api_key=k-123"], shown: "app --api_key=••••"),
        Case(name: "--apiKey=value", arguments: ["app", "--apiKey=k-123"], shown: "app --apiKey=••••"),
        Case(name: "API_KEY=value", arguments: ["env", "API_KEY=k-123", "app"], shown: "env API_KEY=•••• app"),
        Case(name: "--client-secret value", arguments: ["app", "--client-secret", "s"], shown: "app --client-secret ••••"),
        Case(name: "--secret=value", arguments: ["app", "--secret=s"], shown: "app --secret=••••"),
        Case(name: "Authorization: Bearer", arguments: ["curl", "-H", "Authorization: Bearer abc.def.ghi"], shown: "curl -H Authorization: Bearer ••••"),
        Case(name: "--bearer value", arguments: ["app", "--bearer", "xyz"], shown: "app --bearer ••••"),
        Case(name: "redis --requirepass value", arguments: ["redis-server", "--requirepass", "hunter2", "--port", "6379"], shown: "redis-server --requirepass •••• --port 6379"),
        Case(name: "a password with a space", arguments: ["app", "--password=two words"], shown: "app --password=••••"),
        Case(name: "upper case name", arguments: ["app", "--PASSWORD=x"], shown: "app --PASSWORD=••••"),
        Case(name: "camel case name", arguments: ["app", "--accessToken=x"], shown: "app --accessToken=••••"),
        Case(name: "a parameter in a query string", arguments: ["app", "https://h/p?x=1&token=abc&y=2"], shown: "app https://h/p?x=1&token=••••&y=2"),
        Case(name: "a secret inside another assignment", arguments: ["app", "--env=DB_PASSWORD=x"], shown: "app --env=DB_PASSWORD=••••"),
        Case(name: "two secrets", arguments: ["app", "--password=a", "--token", "b"], shown: "app --password=•••• --token ••••"),
    ]

    /// What is not a secret and must stay as it is: a mask that reaches this far would hide what a developer needs to read.
    nonisolated static let visible: [Case] = [
        Case(name: "--port 5432", arguments: ["app", "--port", "5432"], shown: "app --port 5432"),
        Case(name: "--keep-alive", arguments: ["app", "--keep-alive", "--port=3000"], shown: "app --keep-alive --port=3000"),
        Case(name: "--max-tokens 100", arguments: ["app", "--max-tokens", "100"], shown: "app --max-tokens 100"),
        Case(name: "--tokenizer", arguments: ["app", "--tokenizer", "gpt"], shown: "app --tokenizer gpt"),
        Case(name: "--bypass-cache", arguments: ["app", "--bypass-cache", "x"], shown: "app --bypass-cache x"),
        Case(name: "--password-file points at a secret, it is not one", arguments: ["app", "--password-file", "/run/secrets/db"], shown: "app --password-file /run/secrets/db"),
        Case(name: "--token-file=", arguments: ["app", "--token-file=/run/token"], shown: "app --token-file=/run/token"),
        Case(name: "--password-stdin", arguments: ["app", "--password-stdin", "x"], shown: "app --password-stdin x"),
        Case(name: "--pass-through", arguments: ["app", "--pass-through", "x"], shown: "app --pass-through x"),
        Case(name: "psql -p is the port", arguments: ["psql", "-h", "localhost", "-p", "5432"], shown: "psql -h localhost -p 5432"),
        Case(name: "psql -p5432 is the port", arguments: ["psql", "-p5432"], shown: "psql -p5432"),
        Case(name: "mysql -p alone asks, the next one is the database", arguments: ["mysql", "-p", "mydb"], shown: "mysql -p mydb"),
        Case(name: "a flag without a value after --password", arguments: ["app", "--password", "--verbose"], shown: "app --password --verbose"),
        Case(name: "--password as the last argument", arguments: ["app", "--password"], shown: "app --password"),
        Case(name: "a user name in a URL is not a password", arguments: ["app", "ssh://git@host/repo"], shown: "app ssh://git@host/repo"),
        Case(name: "a URL without credentials", arguments: ["app", "--url=http://localhost:8080/path?x=1"], shown: "app --url=http://localhost:8080/path?x=1"),
        Case(name: "a plain script and flags", arguments: ["python3", "-m", "http.server", "8000", "--bind", "127.0.0.1"], shown: "python3 -m http.server 8000 --bind 127.0.0.1"),
        Case(name: "--key alone", arguments: ["app", "--key", "id_rsa"], shown: "app --key id_rsa"),
        Case(name: "--author is not auth", arguments: ["app", "--author=Bob"], shown: "app --author=Bob"),
    ]

    @Test(arguments: hidden) func aSecretIsHiddenAndItsNameKept(_ example: Case) throws {
        let line = try #require(ProcArguments.display(example.arguments))
        #expect(line == example.shown)
    }

    @Test(arguments: visible) func whatIsNotASecretStaysAsItIs(_ example: Case) throws {
        let line = try #require(ProcArguments.display(example.arguments))
        #expect(line == example.shown)
    }

    @Test func theTableHasEnoughToTrustItBothWays() {
        #expect(Self.hidden.count + Self.visible.count >= 15)
        #expect(Self.visible.count >= 8, "false positives are half of the point")
    }

    @Test func noHiddenValueSurvivesInTheLine() throws {
        let secrets = ["hunter2", "abc123", "s3cret", "k-123", "abc.def.ghi", "two words"]
        for example in Self.hidden {
            let line = try #require(ProcArguments.display(example.arguments))
            for secret in secrets { #expect(!line.contains(secret), Comment(rawValue: "\(example.name): \(line)")) }
        }
    }

    @Test func aSecretIsMaskedBeforeALongLineIsCut() throws {
        // Cut first and the end of a long password would be left bare once the mask no longer fits around it.
        let line = try #require(ProcArguments.display(["app", String(repeating: "a", count: 190), "--password=hunter2"], limit: 200))
        #expect(!line.contains("hunter2"))
        let tail = try #require(ProcArguments.display(["app", "--password=" + String(repeating: "x", count: 500)], limit: 50))
        #expect(!tail.contains("xxxx"))
    }

    @Test func theMaskDoesNotChangeTheArgumentsThatAreNotSecrets() {
        let arguments = ["node", "/Users/me/app/server.js", "--port", "3000", "--watch"]
        #expect(SecretMask.mask(arguments) == arguments)
        #expect(SecretMask.mask([]) == [])
        #expect(SecretMask.mask(["app", "naïve=①", "--token", "ünï"]) == ["app", "naïve=①", "--token", "••••"])
    }

    @Test func aNonAsciiValueAfterASecretNameIsMaskedWholeToo() {
        #expect(SecretMask.mask(["app", "--password=pässwörd✓"]) == ["app", "--password=••••"])
        #expect(SecretMask.mask(["app", "https://h/?token=é✓&x=1"]) == ["app", "https://h/?token=••••&x=1"])
    }

    @Test func namesAreSplitIntoWords() {
        #expect(SecretMask.words(in: "--access-token") == ["access", "token"])
        #expect(SecretMask.words(in: "DB_PASSWORD") == ["db", "password"])
        #expect(SecretMask.words(in: "clientSecret") == ["client", "secret"])
        #expect(SecretMask.words(in: "APIKEY") == ["apikey"])
        #expect(SecretMask.isSecretName("--api-key"))
        #expect(!SecretMask.isSecretName("--keep-alive"))
    }
}
