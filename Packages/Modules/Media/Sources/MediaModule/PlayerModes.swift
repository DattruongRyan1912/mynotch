import Foundation

/// The player's shuffle mode, by the ids the adapter reports as `shuffleMode` and takes in `shuffle MODE` (README).
nonisolated enum ShuffleMode: Int, CaseIterable, Sendable {
    case off = 1, albums = 2, tracks = 3

    /// A mode that is not one of the three (a player's own idea of "default") counts as off.
    init(reported value: Double) {
        self = Int(exactly: value).flatMap(Self.init(rawValue:)) ?? .off
    }

    var isOn: Bool { self != .off }

    /// What a tap sets: shuffle comes on for the tracks, whatever mode is on goes off.
    var toggled: ShuffleMode { isOn ? .off : .tracks }
}

/// The player's repeat mode, by the ids the adapter reports as `repeatMode` and takes in `repeat MODE` (README).
nonisolated enum RepeatMode: Int, CaseIterable, Sendable {
    case off = 1, track = 2, playlist = 3

    init(reported value: Double) {
        self = Int(exactly: value).flatMap(Self.init(rawValue:)) ?? .off
    }

    /// What a tap sets: off, then all, then one, then off again, as the players' own buttons go.
    var next: RepeatMode {
        switch self {
        case .off: .playlist
        case .playlist: .track
        case .track: .off
        }
    }
}
