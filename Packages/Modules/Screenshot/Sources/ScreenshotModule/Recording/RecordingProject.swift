import Foundation

/// `project.json`: what a recording is, and later what was done to it. The folder is
/// `<storage>/Recordings/<uuid>/` and holds the segments, `activity.json` and this file.
nonisolated struct RecordingProject: Codable, Equatable, Sendable, Identifiable {
    enum Status: String, Codable, Sendable {
        /// Being recorded, or the app ended while it was (what a crash leaves behind).
        case recording
        case finished
        /// Cut short, and rescued: what could be read of it was kept.
        case interrupted
    }

    nonisolated struct Segment: Codable, Equatable, Sendable {
        /// A file in the folder: `segment-001.mov`. Each pause starts a new one.
        var fileName: String
        /// Where the first frame sits on the capture clock; nil for a segment found by the rescue, which never learned it.
        var captureStart: TimeInterval?
        /// Seconds of video, which the picture and the activity are both measured in.
        var duration: TimeInterval
        var frames = 0
        /// What the encoder could not take in time, for the person who wonders why the video stutters.
        var droppedFrames = 0
        var droppedAudio = 0
    }

    static let fileName = "project.json"

    var version = 1
    var id: UUID
    var createdAt: Date
    var status: Status
    var region: RecordingRegion
    var fps: Int
    var hasMicrophone: Bool
    var hasSystemAudio: Bool
    var segments: [Segment]

    var duration: TimeInterval { segments.reduce(0) { $0 + $1.duration } }
    /// A recording that stopped before the person stopped it, and was rescued.
    var isIncomplete: Bool { status == .interrupted }

    init(
        id: UUID, createdAt: Date, status: Status, region: RecordingRegion, fps: Int, hasMicrophone: Bool, hasSystemAudio: Bool,
        segments: [Segment] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.status = status
        self.region = region
        self.fps = fps
        self.hasMicrophone = hasMicrophone
        self.hasSystemAudio = hasSystemAudio
        self.segments = segments
    }

    func write(to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: folder.appending(path: Self.fileName), options: .atomic)
    }

    static func load(from folder: URL) throws -> RecordingProject {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecordingProject.self, from: Data(contentsOf: folder.appending(path: fileName)))
    }
}

nonisolated extension RecordingProject {
    /// Fields later versions add are read with a default when a file has none, so an older file still opens.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        status = try container.decode(Status.self, forKey: .status)
        region = try container.decode(RecordingRegion.self, forKey: .region)
        fps = try container.decodeIfPresent(Int.self, forKey: .fps) ?? 60
        hasMicrophone = try container.decodeIfPresent(Bool.self, forKey: .hasMicrophone) ?? false
        hasSystemAudio = try container.decodeIfPresent(Bool.self, forKey: .hasSystemAudio) ?? false
        segments = try container.decodeIfPresent([Segment].self, forKey: .segments) ?? []
    }
}

nonisolated extension RecordingProject.Segment {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileName = try container.decode(String.self, forKey: .fileName)
        captureStart = try container.decodeIfPresent(TimeInterval.self, forKey: .captureStart)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        frames = try container.decodeIfPresent(Int.self, forKey: .frames) ?? 0
        droppedFrames = try container.decodeIfPresent(Int.self, forKey: .droppedFrames) ?? 0
        droppedAudio = try container.decodeIfPresent(Int.self, forKey: .droppedAudio) ?? 0
    }
}
