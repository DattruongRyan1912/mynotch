import AppKit
import Foundation
import Testing
@testable import ClipboardModule

/// A history with one item of every kind, boards, a secret and an image stored in a folder of its own, all synthetic and in a
/// temporary folder that goes with the object. What the backup tests export, damage and import.
final class BackupWorld {
    static let base = Date(timeIntervalSince1970: 1_700_000_000.5)
    static let secretText = "mật khẩu 123"
    static let swiftCode = "let x = 1\nprint(x)\nfunc total() -> Int { return x }"

    let root: URL
    /// Where the history's image files are, as the store keeps them.
    let sourceImages: URL
    /// Where an import writes the images it adds.
    let restoredImages: URL
    /// A real file the `.files` item points to, and one that is not there.
    let presentFile: URL
    let missingFile = URL(fileURLWithPath: "/nonexistent-mynotch-test/b.txt")
    let firstPNG = ClipboardClassifierTests.bitmap(pixelsWide: 2, pixelsHigh: 3).representation(using: .png, properties: [:])!
    let secondPNG = ClipboardClassifierTests.bitmap(pixelsWide: 5, pixelsHigh: 4).representation(using: .png, properties: [:])!
    private(set) var history = ClipboardHistory()
    private(set) var imageURLs: [String: URL] = [:]
    /// Item ids by a short label.
    private(set) var ids: [String: UUID] = [:]
    private(set) var boardIDs: [String: UUID] = [:]

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "BackupWorld-\(UUID().uuidString)", directoryHint: .isDirectory)
        sourceImages = root.appending(path: "images", directoryHint: .isDirectory)
        restoredImages = root.appending(path: "restored", directoryHint: .isDirectory)
        presentFile = root.appending(path: "present.txt")
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: sourceImages, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: restoredImages, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: presentFile)

        let rtf = Data(#"{\rtf1\ansi {\b Bold} line}"#.utf8)
        add("text", .text("Xin chào"), source: ("com.apple.Safari", "Safari"))
        add("rich", .richText(plain: "Bold line", rtf: rtf), source: ("com.apple.TextEdit", "TextEdit"))
        add("link", .link(URL(string: "https://example.com/a?b=1")!), source: ("com.google.Chrome", "Chrome"))
        add("hex", .color(hex: "#FF8800"), source: (nil, nil))
        add("rgb", .color(hex: "#33669980", original: "rgba(51, 102, 153, 0.5)"), source: ("com.figma.Desktop", "Figma"))
        add("image", try image(firstPNG, width: 2, height: 3), source: ("com.apple.Preview", "Preview"))
        add("image2", try image(secondPNG, width: 5, height: 4), source: ("com.apple.Preview", "Preview"))
        add("files", .files([presentFile, missingFile]), source: ("com.apple.finder", "Finder"))
        add("code", .text(Self.swiftCode), source: ("com.apple.dt.Xcode", "Xcode"))
        add("secret", .text(Self.secretText), source: ("com.1password.1password", "1Password"), sensitive: true)

        boardIDs["work"] = history.createBoard(name: "Công việc", systemImage: "briefcase", color: .orange)
        boardIDs["photos"] = history.createBoard(name: "Ảnh", systemImage: "photo")
        boardIDs["empty"] = history.createBoard(name: "Trống", systemImage: "star", color: .pink)
        boardIDs["secrets"] = history.createBoard(name: "Bí mật", systemImage: "lock", color: .gray)
        history.pin(itemID: id("text"), to: boardIDs["work"]!)
        history.pin(itemID: id("code"), to: boardIDs["work"]!)
        history.pin(itemID: id("image"), to: boardIDs["photos"]!)
        history.pin(itemID: id("secret"), to: boardIDs["secrets"]!)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func id(_ label: String) -> UUID {
        ids[label]!
    }

    func item(_ label: String) -> ClipboardItem {
        history.items.first(where: { $0.id == ids[label] })!
    }

    /// Adds an item copied a minute after the one before, as the module adds it.
    @discardableResult
    func add(_ label: String, _ content: ClipboardContent, source: (String?, String?), sensitive: Bool = false) -> UUID {
        let date = Self.base.addingTimeInterval(TimeInterval(history.items.count) * 60)
        let id = history.add(content, hash: ClipboardContent.hash(of: content), source: source, at: date, isSensitive: sensitive).id
        ids[label] = id
        return id
    }

    /// An image item whose file is written into `sourceImages` under its hash name.
    func image(_ png: Data, width: Int, height: Int) throws -> ClipboardContent {
        let name = png.sha256Hex + ".png"
        let url = sourceImages.appending(path: name)
        try png.write(to: url)
        imageURLs[name] = url
        return .image(ClipboardImage(fileName: name, pixelWidth: width, pixelHeight: height, byteCount: png.count))
    }

    func replaceHistory(_ new: ClipboardHistory) {
        history = new
    }

    /// A file in the world's folder.
    func file(_ name: String) -> URL {
        root.appending(path: name)
    }

    func export(
        _ options: ClipboardBackupOptions = ClipboardBackupOptions(), as name: String = "backup.mynotchclip",
        history: ClipboardHistory? = nil, limits: ZipLimits = ClipboardBackupFormat.limits,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> (url: URL, summary: ClipboardBackupExportSummary) {
        let url = file(name)
        let summary = try await ClipboardBackupWriter.write(
            history: history ?? self.history, options: options, imageURLs: imageURLs, to: url,
            now: Self.base.addingTimeInterval(10_000), limits: limits, progress: progress
        )
        return (url, summary)
    }

    func plan(
        _ url: URL, known: Set<String> = [], limits: ZipLimits = ClipboardBackupFormat.limits,
        now: Date = BackupWorld.base.addingTimeInterval(20_000), progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> ClipboardRestorePlan {
        try await ClipboardBackupReader.plan(
            archiveAt: url, knownHashes: known, imagesDirectory: restoredImages, now: now, limits: limits, progress: progress
        )
    }

    /// Exports and imports into `existing`, returning the history after the merge.
    func roundTrip(
        _ options: ClipboardBackupOptions = ClipboardBackupOptions(skipSensitive: false), into existing: ClipboardHistory = ClipboardHistory()
    ) async throws -> (history: ClipboardHistory, plan: ClipboardRestorePlan, result: ClipboardHistory.RestoreResult) {
        let (url, _) = try await export(options)
        let plan = try await plan(url, known: Set(existing.items.map(\.contentHash)))
        var merged = existing
        let result = merged.restore(plan)
        return (merged, plan, result)
    }

    // MARK: Crafting archives

    /// A manifest as JSON, with the fields a reader needs unless overridden; `extra` adds or replaces top-level keys.
    static func manifest(
        version: Int = 1, format: String = ClipboardBackupFormat.formatName, items: [[String: Any]] = [], boards: [[String: Any]] = [],
        extra: [String: Any] = [:]
    ) -> Data {
        var object: [String: Any] = [
            "format": format, "version": version, "createdAt": 1_700_000_000.0, "scope": "all", "includesSensitive": false,
            "items": items, "boards": boards,
        ]
        for (key, value) in extra { object[key] = value }
        return try! JSONSerialization.data(withJSONObject: object)
    }

    static func manifestItem(_ id: UUID, kind: String = "text", copiedAt: Double = 1_700_000_100, extra: [String: Any] = [:]) -> [String: Any] {
        var object: [String: Any] = ["id": id.uuidString, "kind": kind, "copiedAt": copiedAt]
        for (key, value) in extra { object[key] = value }
        return object
    }

    /// An archive holding the manifest and whatever else, named as given.
    @discardableResult
    func craft(
        manifest: Data = BackupWorld.manifest(), entries: [(name: String, data: Data, mode: UInt16)] = [], as name: String = "crafted.mynotchclip"
    ) throws -> URL {
        let url = file(name)
        let writer = try ZipWriter(url: url)
        try writer.add(name: ClipboardBackupFormat.manifestName, data: manifest)
        for entry in entries { try writer.add(name: entry.name, data: entry.data, mode: entry.mode) }
        try writer.finish()
        return url
    }

    static func payload(_ id: UUID, _ ext: String) -> String {
        "items/\(id.uuidString).\(ext)"
    }

    /// Everything a backup archive holds, for tests that look at its content.
    func contents(of url: URL) throws -> (names: [String], manifest: [String: Any], payloads: [String: Data]) {
        let reader = try ZipReader(url: url, limits: .unlimited)
        var payloads: [String: Data] = [:]
        for entry in reader.entries where entry.name != ClipboardBackupFormat.manifestName {
            payloads[entry.name] = try reader.data(of: entry)
        }
        let manifest = try JSONSerialization.jsonObject(with: try #require(try reader.data(named: ClipboardBackupFormat.manifestName))) as! [String: Any]
        return (reader.entries.map(\.name), manifest, payloads)
    }

    func manifestItems(_ manifest: [String: Any]) -> [[String: Any]] {
        manifest["items"] as? [[String: Any]] ?? []
    }

    /// What identifies an item apart from its id, which an import makes anew.
    struct Essence: Equatable {
        let content: ClipboardContent
        let hash: String
        let copiedAt: Int
        let bundleID: String?
        let appName: String?
        let code: CodeDetection?
        let sensitive: Bool

        init(_ item: ClipboardItem) {
            content = item.content
            hash = item.contentHash
            copiedAt = Int((item.copiedAt.timeIntervalSince1970 * 1000).rounded())
            bundleID = item.sourceBundleID
            appName = item.sourceAppName
            code = item.codeDetection
            sensitive = item.isSensitive
        }
    }

    func essences(_ history: ClipboardHistory) -> [Essence] {
        history.items.map(Essence.init)
    }
}
