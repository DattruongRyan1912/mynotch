import Foundation
import Observation

/// The subtitles the user loaded, each for the video it was loaded for, with how far it was moved to fit that copy of the film.
/// They are kept in one file of the module's storage, the cues copied in, so a film opened again gets its subtitles back even when
/// the file was moved or deleted. The Media tab reads it for the video playing now (`current`).
@Observable
final class SubtitleBook {
    /// From `from` seconds into the video on (until the next part), the cues are moved by `delay`: what an advertisement spliced into
    /// the video does to everything after it.
    struct DelayPart: Codable, Equatable {
        var from: Double
        var delay: Double
    }

    struct Entry: Codable, Equatable {
        /// The file's name, for the tab.
        var name: String
        var cues: [SubtitleCue]
        /// Seconds the cues are moved by before the first of `parts`, all of them without parts: positive shows them later.
        var delay: Double
        /// The oldest are let go first once there are more than `maxEntries`.
        var usedAt: Date
        /// Later parts of the video moved by other delays, in order. None in a file written before there were parts.
        var parts: [DelayPart] = []

        init(name: String, cues: [SubtitleCue], delay: Double, usedAt: Date, parts: [DelayPart] = []) {
            self.name = name
            self.cues = cues
            self.delay = delay
            self.usedAt = usedAt
            self.parts = parts
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            cues = try container.decode([SubtitleCue].self, forKey: .cues)
            delay = try container.decode(Double.self, forKey: .delay)
            usedAt = try container.decode(Date.self, forKey: .usedAt)
            parts = try container.decodeIfPresent([DelayPart].self, forKey: .parts) ?? []
        }

        /// The delay of the part `position` (seconds into the video) is in; the first part's without a position.
        func delay(at position: Double?) -> Double {
            guard let position, let part = parts.last(where: { $0.from <= position }) else { return delay }
            return part.delay
        }

        /// The delay a cue is shown with: that of the last part it falls in once moved by that part's delay.
        func delay(for cue: SubtitleCue) -> Double {
            parts.last(where: { cue.start + $0.delay >= $0.from })?.delay ?? delay
        }

        var isMoved: Bool { delay != 0 || !parts.isEmpty }
    }

    /// A delay found by listening this much away from the one in force is another part of the video (an advertisement came in
    /// between); closer, it only sets the part right.
    static let newPartDifference = 1.0

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

    /// Moves the part of the video `position` is in (the first part without a position), and only that part.
    func shift(by seconds: Double, at position: Double? = nil) {
        guard let currentKey, var entry = entries[currentKey] else { return }
        if let position, let index = entry.parts.lastIndex(where: { $0.from <= position }) {
            entry.parts[index].delay = Self.tenths(entry.parts[index].delay + seconds)
        } else {
            entry.delay = Self.tenths(entry.delay + seconds)
        }
        entry.usedAt = now()
        entries[currentKey] = entry
        save()
    }

    /// What listening from `from` seconds into the video found, `position` being where it plays now. Far from the delay in force
    /// there, it is a new part from `from` on, and the parts after it, worked out before the latest advertisement, are let go; close,
    /// it sets the part in force right. Subtitles never moved before are moved all through.
    func setDelay(_ delay: Double, from: Double, at position: Double) {
        guard let currentKey, var entry = entries[currentKey] else { return }
        let delay = Self.tenths(delay)
        if !entry.isMoved {
            entry.delay = delay
        } else if abs(delay - entry.delay(at: position)) <= Self.newPartDifference {
            shift(by: delay - entry.delay(at: position), at: position)
            return
        } else {
            entry.parts.removeAll { $0.from >= from }
            entry.parts.append(DelayPart(from: from, delay: delay))
        }
        entry.usedAt = now()
        entries[currentKey] = entry
        save()
    }

    /// No delay anywhere, the parts gone.
    func resetDelay() {
        guard let currentKey, var entry = entries[currentKey], entry.isMoved else { return }
        entry.delay = 0
        entry.parts = []
        entry.usedAt = now()
        entries[currentKey] = entry
        save()
    }

    /// Whole tenths, so steps of 0.5 never add up to 1.4999.
    private static func tenths(_ seconds: Double) -> Double {
        (seconds * 10).rounded() / 10
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
