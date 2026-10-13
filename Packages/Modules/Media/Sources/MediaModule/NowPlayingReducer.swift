import Foundation

/// Folds mediaremote-adapter `stream --micros` lines into a `NowPlayingState`.
///
/// Keeps the merged raw payload rather than only the state, so a diff touching one key
/// (e.g. `playing`) re-derives fields that depend on several keys (the anchor's rate).
nonisolated struct NowPlayingReducer: Sendable {
    nonisolated enum Outcome: Equatable, Sendable {
        case applied
        /// Not a `data` line or not decodable; the state is unchanged.
        case ignored
    }

    private(set) var state = NowPlayingState.empty
    private var payload: [String: JSONValue] = [:]
    /// Base64 text of the current artwork, compared instead of decoding every update (artwork is hundreds of KB).
    private var artworkBase64: String?
    private var artworkRevision = 0

    /// - Parameter receivedAt: when the line arrived. A pause, resume or rate change can arrive before
    ///   the player's fresh elapsed time (~100 ms later, or never); until then the position is anchored here.
    @discardableResult
    mutating func apply(line: String, receivedAt: Date) -> Outcome {
        guard let message = try? JSONDecoder().decode(Message.self, from: Data(line.utf8)), message.type == "data" else {
            return .ignored
        }
        let update = message.payload
        let previousPayload = payload
        let previousState = state
        if update.isEmpty {
            payload = [:]
        } else if message.diff == true {
            for (key, value) in update { payload[key] = value == .null ? nil : value }
        } else {
            payload = update.filter { $0.value != .null }
        }
        let sameTrack = Self.metadata(from: payload).trackIdentity == previousState.trackIdentity
        // Players briefly unload artwork (e.g. while seeking); keep it while the track is the same.
        if message.diff != true, sameTrack, payload["artworkData"] == nil {
            payload["artworkData"] = previousPayload["artworkData"]
            payload["artworkMimeType"] = payload["artworkMimeType"] ?? previousPayload["artworkMimeType"]
        }
        // Without this the old anchor would be re-read at the new rate: pausing snaps back, resuming jumps ahead.
        let playbackChanged = (payload["playing"]?.bool ?? false) != previousState.isPlaying
            || payload["playbackRate"]?.number != previousPayload["playbackRate"]?.number
        let carriesTime = update["elapsedTimeMicros"] != nil || update["timestampEpochMicros"] != nil
        if sameTrack, playbackChanged, !carriesTime, let position = PlaybackClock.position(previousState, at: receivedAt) {
            payload["elapsedTimeMicros"] = .number(position * 1_000_000)
            payload["timestampEpochMicros"] = .number(receivedAt.timeIntervalSince1970 * 1_000_000)
        }
        state = Self.metadata(from: payload)
        state.artwork = artwork(previous: previousState.artwork)
        return .applied
    }

    private mutating func artwork(previous: ArtworkData?) -> ArtworkData? {
        guard let base64 = payload["artworkData"]?.string else {
            artworkBase64 = nil
            return nil
        }
        let mimeType = payload["artworkMimeType"]?.string
        guard base64 != artworkBase64 else {
            return previous.map { ArtworkData(data: $0.data, mimeType: mimeType, revision: $0.revision) }
        }
        artworkBase64 = base64
        artworkRevision += 1
        return Data(base64Encoded: base64).map { ArtworkData(data: $0, mimeType: mimeType, revision: artworkRevision) }
    }

    /// Everything except artwork. Time keys are the `--micros` variants (README `get`, "--micros" table).
    private static func metadata(from payload: [String: JSONValue]) -> NowPlayingState {
        let isPlaying = payload["playing"]?.bool ?? false
        var anchor: PlaybackAnchor?
        if let elapsed = payload["elapsedTimeMicros"]?.number, let timestamp = payload["timestampEpochMicros"]?.number {
            let rate = isPlaying ? payload["playbackRate"]?.number ?? 1 : 0
            anchor = PlaybackAnchor(
                elapsedSeconds: elapsed / 1_000_000,
                timestamp: Date(timeIntervalSince1970: timestamp / 1_000_000),
                rate: rate
            )
        }
        return NowPlayingState(
            bundleIdentifier: payload["bundleIdentifier"]?.string,
            parentApplicationBundleIdentifier: payload["parentApplicationBundleIdentifier"]?.string,
            title: payload["title"]?.string,
            artist: payload["artist"]?.string,
            album: payload["album"]?.string,
            // A non-positive duration gives no length; treat it as unknown so the clock does not pin the position to 0.
            durationSeconds: payload["durationMicros"]?.number.flatMap { $0 > 0 ? $0 / 1_000_000 : nil },
            elapsedAnchor: anchor,
            isPlaying: isPlaying,
            uniqueIdentifier: payload["uniqueIdentifier"]?.identifier,
            contentItemIdentifier: payload["contentItemIdentifier"]?.identifier,
            isAdvertisement: payload["isAdvertisement"]?.bool ?? false
        )
    }

    private nonisolated struct Message: Decodable {
        var type: String
        var diff: Bool?
        var payload: [String: JSONValue]

        private nonisolated enum CodingKeys: String, CodingKey { case type, diff, payload }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            diff = try container.decodeIfPresent(Bool.self, forKey: .diff)
            // A missing payload is malformed; an explicit null, like {}, means nothing is playing.
            payload = try container.decode([String: JSONValue]?.self, forKey: .payload) ?? [:]
        }
    }
}

/// One payload value. Only scalars are read; arrays and objects are kept as `.other`.
nonisolated enum JSONValue: Decodable, Equatable, Sendable {
    case null, bool(Bool), integer(Int64), unsignedInteger(UInt64), number(Double), string(String), other

    /// Integers are tried before `Double` so 64-bit identifiers stay exact.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(UInt64.self) {
            self = .unsignedInteger(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .other
        }
    }

    var bool: Bool? { if case .bool(let value) = self { value } else { nil } }
    var string: String? { if case .string(let value) = self { value } else { nil } }

    var number: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .unsignedInteger(let value): Double(value)
        case .number(let value): value
        default: nil
        }
    }

    /// MediaRemote reports `uniqueIdentifier` as a 64-bit number for some players and a string for others.
    var identifier: String? {
        switch self {
        case .string(let value): value
        case .integer(let value): String(value)
        case .unsignedInteger(let value): String(value)
        case .number(let value): String(value)
        default: nil
        }
    }
}
