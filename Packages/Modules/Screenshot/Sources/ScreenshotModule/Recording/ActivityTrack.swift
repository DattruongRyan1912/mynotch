import Foundation

nonisolated enum ClickButton: String, Codable, Sendable {
    case left, right
}

/// What the pointer and keyboard did during a recording: the file `activity.json`, next to the segments.
///
/// Times are seconds into the recording (pauses take no time, as in the video). Positions are pixels of the video, origin at
/// its top-left, y down, and are not clamped: the pointer can leave the recorded region. Keys carry a time and nothing else.
nonisolated struct ActivityTrack: Codable, Equatable, Sendable {
    nonisolated struct Pointer: Codable, Equatable, Sendable {
        var t: TimeInterval
        var x: Double
        var y: Double
    }

    nonisolated struct Click: Codable, Equatable, Sendable {
        var t: TimeInterval
        var x: Double
        var y: Double
        var button: ClickButton
    }

    static let fileName = "activity.json"

    var version = 1
    /// The video's size, the space the positions are in.
    var pixelWidth: Int
    var pixelHeight: Int
    /// False when Accessibility was missing: `keys` is empty because nothing could be seen, not because nothing was typed.
    var keyboardRecorded: Bool
    /// Where the pointer moved, only when its position changed.
    var pointer: [Pointer] = []
    var clicks: [Click] = []
    /// When a key went down.
    var keys: [TimeInterval] = []

    /// The track without what lies beyond `duration`, for a recording that lost its tail.
    func trimmed(to duration: TimeInterval) -> ActivityTrack {
        var copy = self
        copy.pointer.removeAll { $0.t > duration }
        copy.clicks.removeAll { $0.t > duration }
        copy.keys.removeAll { $0 > duration }
        return copy
    }

    func write(to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: folder.appending(path: Self.fileName), options: .atomic)
    }

    static func load(from folder: URL) throws -> ActivityTrack {
        try JSONDecoder().decode(ActivityTrack.self, from: Data(contentsOf: folder.appending(path: fileName)))
    }
}
