import Foundation
import Observation

/// The subtitles the user loaded, each for the video it was loaded for, with how far it was moved to fit that copy of the film.
/// They are kept in one file of the module's storage, the cues copied in, so a film opened again gets its subtitles back even when
/// the file was moved or deleted. The Media tab reads it for the video playing now (`current`).
@Observable
final class SubtitleBook {
    struct Entry: Codable, Equatable {
        /// The file's name, for the tab.
        var name: String
        var cues: [SubtitleCue]
        /// Seconds every cue is moved by: positive shows the subtitles later.
        var delay: Double
        /// The oldest are let go first once there are more than `maxEntries`.
        var usedAt: Date
    }

    /// Films remembered; a subtitle file is some hundreds of kilobytes of cues.
    static let maxEntries = 30
    /// What one press of the tab's buttons moves the subtitles by, and the larger step of the menu.
    static let smallStep = 0.5
    static let largeStep = 5.0
    static let fileName = "subtitles.json"

    private(set) var entries: [String: Entry] = [:]
    /// Which video the module is following now, nil while nothing plays.
    private(set) var currentKey: String?
    /// The name of the last file that held no subtitle, until another is loaded or the video changes.
    private(set) var unreadableName: String?

    private var fileURL: URL?
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    var current: Entry? { currentKey.flatMap { entries[$0] } }

    /// The video a state plays, as subtitles are remembered: the player and the title, spelled the same whatever its case and
    /// spacing. nil while nothing plays.
    static func key(for state: NowPlayingState) -> String? {
        guard state.isActive, let player = state.playerBundleIdentifier, let title = state.title else { return nil }
        return player + "\n" + YouTubeCaptionMatcher.normalised(title)
    }

    /// Reads what was kept in `directory`; an unreadable file is as good as none.
    func open(directory: URL) {
        fileURL = directory.appending(path: Self.fileName)
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            entries = [:]
            return
        }
        entries = saved
    }

    func close() {
        fileURL = nil
        entries = [:]
        currentKey = nil
        unreadableName = nil
    }

    func setCurrentKey(_ key: String?) {
        guard key != currentKey else { return }
        currentKey = key
        if unreadableName != nil { unreadableName = nil }
    }

    /// Loads the file for the current video, in place of what it had. False, and nothing changes, when the file holds no subtitle.
    @discardableResult
    func load(_ data: Data, name: String) -> Bool {
        guard let currentKey else { return false }
        guard let cues = SubtitleParser.cues(from: data) else {
            unreadableName = name
            return false
        }
        unreadableName = nil
        entries[currentKey] = Entry(name: name, cues: cues, delay: 0, usedAt: now())
        trim()
        save()
        return true
    }

    func shift(by seconds: Double) {
        guard let currentKey, var entry = entries[currentKey] else { return }
        // Whole tenths, so steps of 0.5 never add up to 1.4999.
        entry.delay = ((entry.delay + seconds) * 10).rounded() / 10
        entry.usedAt = now()
        entries[currentKey] = entry
        save()
    }

    func resetDelay() {
        guard let delay = current?.delay, delay != 0 else { return }
        shift(by: -delay)
    }

    func remove() {
        guard let currentKey, entries[currentKey] != nil else { return }
        entries[currentKey] = nil
        save()
    }

    private func trim() {
        guard entries.count > Self.maxEntries else { return }
        let oldest = entries.sorted { $0.value.usedAt < $1.value.usedAt }.prefix(entries.count - Self.maxEntries)
        for (key, _) in oldest { entries[key] = nil }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            // The subtitles still show for as long as the app runs; only remembering them is lost.
        }
    }
}
