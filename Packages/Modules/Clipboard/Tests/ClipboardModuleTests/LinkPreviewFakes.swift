import AppKit
import CoreGraphics
import Foundation
import ImageIO
import MyNotchCore
import MyNotchTestSupport
import Testing
import UniformTypeIdentifiers
@testable import ClipboardModule

/// Pictures made for the tests, flat grey, so a test knows exactly how many pixels it is giving the decoder.
nonisolated enum TestPictures {
    static func image(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func encoded(_ frames: [(width: Int, height: Int)], as type: UTType) -> Data {
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, frames.count, nil)!
        for frame in frames { CGImageDestinationAddImage(destination, image(width: frame.width, height: frame.height), nil) }
        precondition(CGImageDestinationFinalize(destination))
        return output as Data
    }

    static func png(width: Int, height: Int) -> Data {
        encoded([(width, height)], as: .png)
    }

    /// A 64 x 48 WebP, which ImageIO reads and MyNotch must not be given by a page (made with Pillow; the bytes are the file's).
    static let webp = Data(base64Encoded: "UklGRkAAAABXRUJQVlA4IDQAAABQAwCdASpAADAAPm02mUkkIyKhIqgAgA2JaQAAGHCT276rwADxjtk70v9yfh7Ywv4AAAAA")!

    /// An icon file with three pictures in it, 16, 32 and 128 pixels square, the biggest last (made with Pillow).
    static let icoThreeFrames = Data(base64Encoded: """
    AAABAAMAEBAAAAAAIABeAAAANgAAACAgAAAAACAAcQAAAJQAAACAgAAAAAAgAIsBAAAFAQAAiVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAJUlEQVR4nGPkOiH3n4ECwES\
    J5lEDIICJgULANGoAw2gYMFAeBgAaiAIPQUTXNQAAAABJRU5ErkJggolQTkcNChoKAAAADUlIRFIAAAAgAAAAIAgGAAAAc3p69AAAADhJREFUeJzt0EERADAIA0HKExH4l1JXZaqCz8bAZfbU7ReLy824AwQIECBAgAABAgQIECBAgMAXGD3/Ai/+rD8LAAAAAElFTkSuQmCCiVBORw0KGgoAAAANSUhEUgAAAIAAAACACAYAAADDPmHLAAABUklEQVR4nO3SMQHAIADAsLETEfiXgiuQwdFEQY+Oudf5yPpfB/CWAeIMEGeAOAPEGSDOAHEGiDNAnAHiDBBngDgDxBkgzgBxBogzQJwB4gwQZ4A4A8QZIM4AcQaIM0CcAeIMEGeAOAPEGSDOAHEGiDNAnAHiDBBngDgDxBkgzgBxBogzQJwB4gwQZ4A4A8QZIM4AcQaIM0CcAeIMEGeAOAPEGSDOAHEGiDNAnAHiDBBngDgDxBkgzgBxBogzQJwB4gwQZ4A4A8QZIM4AcQaIM0CcAeIMEGeAOAPEGSDOAHEGiDNAnAHiDBBngDgDxBkgzgBxBogzQJwB4gwQZ4A4A8QZIM4AcQaIM0CcAeIMEGeAOAPEGSDOAHEGiDNAnAHiDBBngDgDxBkgzgBxBogzQJwB4gwQZ4A4A8QZIM4AcQaIM0CcAeIMEGeAOAPEGSDOAHEXVq8C712jbBEAAAAASUVORK5CYII=
    """)!

    /// The size of a stored PNG, read the way the app reads one.
    static func size(of png: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }
}

nonisolated extension ClipboardLinkResponse {
    static func html(_ text: String, status: Int = 200, type: String? = "text/html; charset=utf-8", cut: Bool = false) -> Self {
        Self(status: status, contentType: type, location: nil, body: Data(text.utf8), wasCut: cut)
    }

    static func picture(_ data: Data, type: String? = "image/png", status: Int = 200, cut: Bool = false) -> Self {
        Self(status: status, contentType: type, location: nil, body: data, wasCut: cut)
    }

    static func redirect(to location: String?, status: Int = 302) -> Self {
        Self(status: status, contentType: nil, location: location, body: Data(), wasCut: false)
    }

    static func status(_ code: Int) -> Self {
        Self(status: code, contentType: "text/html", location: nil, body: Data(), wasCut: false)
    }
}

/// Answers from a table, records every request and every lookup, and opens no connection. A name with no entry resolves to a public address.
nonisolated final class FakeLinkTransport: ClipboardLinkTransport, @unchecked Sendable {
    typealias Handler = @Sendable (ClipboardLinkRequest) async throws -> ClipboardLinkResponse

    static let publicAddress = "93.184.216.34"

    private let lock = NSLock()
    private var log: [ClipboardLinkRequest] = []
    private var lookupLog: [String] = []
    private var table: [String: ClipboardLinkResponse] = [:]
    private var hosts: [String: [String]] = [:]
    private var handler: Handler?
    private var lookupHandler: (@Sendable (String) async -> [String])?
    private var running = 0
    private var mostRunning = 0

    init(_ table: [String: ClipboardLinkResponse] = [:], handler: Handler? = nil) {
        self.table = table
        self.handler = handler
    }

    var requests: [ClipboardLinkRequest] { locked { log } }
    var requestedURLs: [String] { locked { log.map(\.url.absoluteString) } }
    var lookups: [String] { locked { lookupLog } }
    /// The most requests that were waiting for an answer at the same time.
    var mostAtOnce: Int { locked { mostRunning } }

    func set(_ url: String, _ response: ClipboardLinkResponse) {
        locked { table[url] = response }
    }

    func tableLookup(_ url: String) -> ClipboardLinkResponse? {
        locked { table[url] }
    }

    func setHost(_ host: String, resolvesTo addresses: [String]) {
        locked { hosts[host] = addresses }
    }

    func setHandler(_ new: Handler?) {
        locked { handler = new }
    }

    func setLookupHandler(_ new: (@Sendable (String) async -> [String])?) {
        locked { lookupHandler = new }
    }

    private func locked<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func get(_ request: ClipboardLinkRequest) async throws -> ClipboardLinkResponse {
        let (handler, answer) = locked { () -> (Handler?, ClipboardLinkResponse?) in
            log.append(request)
            running += 1
            mostRunning = max(mostRunning, running)
            return (self.handler, table[request.url.absoluteString])
        }
        defer { locked { running -= 1 } }
        if let handler { return try await handler(request) }
        return answer ?? .status(404)
    }

    func addresses(for host: String) async -> [String] {
        let (handler, known) = locked { () -> ((@Sendable (String) async -> [String])?, [String]?) in
            lookupLog.append(host)
            return (lookupHandler, hosts[host])
        }
        if let handler { return await handler(host) }
        return known ?? [Self.publicAddress]
    }
}

/// Holds requests until the test lets them go, so a test can change the world while a read is under way.
nonisolated final class LinkGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                waiting.append(continuation)
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let all = waiting
        waiting = []
        lock.unlock()
        all.forEach { $0.resume() }
    }
}

/// How a limit runs out in a test: when the test says, not when a clock does. A busy machine can make a real timer fire before work that was
/// about to finish, and the limits of the code are not what these tests are about when they are not the point.
///
/// The `.timeLimit` of a test that uses these is only there to end a hang (a handler that sleeps for an hour when nothing cancels it), and it
/// is long for that reason: on a machine with other builds running, a whole run of this package lasts a minute or two, and a test that is
/// waiting for a thread of the pool, as every one of them does between two steps, lasts nearly as long. A limit of a minute failed two of them.
nonisolated enum LinkTimers {
    /// Never runs out.
    static let never: ClipboardLinkFetcher.Sleep = { _ in try await Task.sleep(for: .seconds(3600)) }

    /// Runs out, for the limits in `limits`, once `flag` is raised (by a handler that is about to hang); never for the others.
    static func runningOut(_ limits: Set<Duration>, after flag: LinkFlag) -> ClipboardLinkFetcher.Sleep {
        { limit in
            guard limits.contains(limit) else { return try await Task.sleep(for: .seconds(3600)) }
            while !flag.isRaised { try await Task.sleep(for: .milliseconds(1)) }
        }
    }
}

/// Raised by a transport's handler when its request was cancelled.
nonisolated final class LinkFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    var isRaised: Bool {
        lock.lock()
        defer { lock.unlock() }
        return raised
    }

    func raise() {
        lock.lock()
        raised = true
        lock.unlock()
    }
}

final class FakeSoundPlayer: ClipboardSoundPlaying {
    private(set) var played: [ClipboardSound] = []

    func play(_ sound: ClipboardSound) {
        played.append(sound)
    }
}

final class FakeSoundClock {
    var seconds: Double = 1_000
    func advance(by delta: Double) { seconds += delta }
}

/// A started module with the optional features wired to fakes: a sound player that counts, a clock that stands still, and a transport that
/// answers from a table. Nothing reaches the speaker, the system pasteboard or the network.
final class OptionalFeaturesFixture {
    let pasteboard = FakePasteboard()
    let keystrokes = FakeKeystrokeSender()
    let panelWindow = FakePanelWindow()
    let system = FakeSystem()
    let modifiers = FakeModifierState()
    let keychain = FakeBoardKeychain()
    let authenticator = FakeAuthenticator()
    let sounds = FakeSoundPlayer()
    let clock = FakeSoundClock()
    let transport: FakeLinkTransport
    let module: ClipboardModule
    let harness: RegistryHarness
    let temporaryRoot: URL

    static let password = "mật khẩu của tôi"
    static let fast = ClipboardVaultCrypto.Derivation(iterations: 1_000, minimumIterations: 1_000)

    init(
        transport: FakeLinkTransport = FakeLinkTransport(), timeouts: (request: Duration, total: Duration) = (.seconds(5), .seconds(20)),
        sleep: @escaping ClipboardLinkFetcher.Sleep = LinkTimers.never
    ) {
        self.transport = transport
        let system = system
        let clock = clock
        module = ClipboardModule(
            pasteboard: pasteboard, keystrokes: keystrokes,
            frontmostApp: { system.frontmost }, isTrusted: { system.trusted },
            pasteboardAccessBehavior: { system.accessBehavior }, modifiers: modifiers, now: { system.now },
            libraryWindow: FakeLibraryWindow(), panelWindow: panelWindow, libraryPreview: FakePreviewWindow(),
            panelPreview: FakePreviewWindow(), tabPreview: FakePreviewWindow(),
            keychain: keychain, authenticator: authenticator, keyDerivation: Self.fast,
            soundPlayer: sounds, soundClock: { clock.seconds }, linkTransport: transport, linkTimeouts: timeouts, linkSleep: sleep
        )
        harness = RegistryHarness([module])
        temporaryRoot = harness.storageRoot.applicationSupport.deletingLastPathComponent()
    }

    deinit {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    var directory: URL { harness.storageRoot.storage(for: "clipboard").directory }
    var linkPreviewsDirectory: URL { directory.appending(path: "linkpreviews", directoryHint: .isDirectory) }
    var state: ClipboardState { module.state }
    var items: [ClipboardItem] { module.state.history.items }

    func settings() throws -> (ModuleSettings, ClipboardSettingKeys) {
        let settings = try #require(harness.settingsEnvironment(for: "clipboard")).settings
        return (settings, ClipboardSettingKeys(settings))
    }

    func setSounds(_ on: Bool) throws {
        let (settings, keys) = try settings()
        settings.set(on, for: keys.playSounds)
    }

    func setLinkPreviews(_ on: Bool) throws {
        let (settings, keys) = try settings()
        settings.set(on, for: keys.linkPreviews)
    }

    func start() async {
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "clipboard") == .running)
    }

    func restart() async {
        await harness.registry.setEnabled(false, for: "clipboard")
        await harness.registry.setEnabled(true, for: "clipboard")
    }

    /// Another app copies; the next poll records it.
    func copy(_ text: String, extraTypes: [String] = []) {
        pasteboard.copy(PasteboardSnapshot(types: ["public.utf8-plain-text"] + extraTypes, string: text))
        harness.scheduler.advance(by: ClipboardModuleTests.pollInterval)
    }

    func item(_ text: String) throws -> ClipboardItem {
        try #require(items.first { $0.content.plainText == text })
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    func previewFile(of item: ClipboardItem) throws -> URL {
        directory.appending(components: "linkpreviews", try #require(item.linkPreviewFileName))
    }

    /// Waits until no read is waiting or under way. Counted in turns, not read off a clock: when another test holds the main actor for
    /// seconds, a deadline would be over the moment this one runs again, with nothing yet given the chance to finish.
    func waitForLinks(turns: Int = 2_000) async {
        await wait(turns: turns) { module.linkPreviews.running.isEmpty && module.linkPreviews.queue.isEmpty }
    }

    /// Waits until `condition` holds, for a read that is held at a gate.
    func wait(turns: Int = 2_000, until condition: () -> Bool) async {
        var left = turns
        while !condition(), left > 0 {
            try? await Task.sleep(for: .milliseconds(5))
            left -= 1
        }
    }

    /// A board "Két" with `item` pinned to it, locked with a password, and opened again.
    func pinToOpenLockedBoard(_ item: ClipboardItem) async throws -> UUID {
        let board = try #require(module.createBoard(named: "Két"))
        module.pin(item, to: board)
        try await module.lockBoard(board, setup: .password(Self.password))
        try await module.unlockBoard(board, credential: .password(Self.password))
        return board
    }

    /// A page with a title and an `og:image`, and the picture itself, in the table.
    func servePage(_ url: String, title: String = "Trang thử", image: String = "https://cdn.example.com/p.png", size: (Int, Int) = (600, 300)) {
        transport.set(url, .html("<html><head><title>\(title)</title><meta property=\"og:image\" content=\"\(image)\"></head><body></body></html>"))
        transport.set(image, .picture(TestPictures.png(width: size.0, height: size.1)))
    }
}
