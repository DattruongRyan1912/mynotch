import Foundation

/// What a slot beside play and pause can hold. The raw values are what the settings keep, so they never change.
nonisolated enum MediaControlButton: String, CaseIterable, Codable, Sendable {
    case previous
    case next
    case rewind = "rewind15"
    case forward = "forward15"
    case shuffle
    case repeatMode = "repeat"
    case like
    case volume
    case lyrics
    case none

    /// How far the seek buttons go.
    static let seekStep: Double = 15

    /// What the Settings picker offers. Like is left out until the adapter can send it (`NowPlayingSource.canLike`): a heart
    /// that is faded for ever is no choice. Its stored name stays, so a later adapter needs no migration.
    static let choices = allCases.filter { $0 != .like }

    /// The name in Settings.
    var title: String {
        switch self {
        case .previous: "Bài trước"
        case .next: "Bài tiếp theo"
        case .rewind: "Tua lùi 15 giây"
        case .forward: "Tua tới 15 giây"
        case .shuffle: "Phát ngẫu nhiên"
        case .repeatMode: "Lặp lại"
        case .like: "Thích"
        case .volume: "Âm lượng"
        case .lyrics: "Lời bài hát"
        case .none: "Không có"
        }
    }
}

/// The buttons left and right of play and pause, left to right: the two slots on the left, then the two on the right.
nonisolated struct MediaControlLayout: Equatable, Codable, Sendable {
    /// Two on each side of the centre, so the row has five buttons at most.
    static let slotCount = 4

    /// Previous and next close to play and pause, as the row always was.
    static let standard = MediaControlLayout(slots: [.none, .previous, .next, .none])

    private(set) var slots: [MediaControlButton]

    /// Always `slotCount` slots, and a button in one slot only: a later duplicate becomes none.
    init(slots: [MediaControlButton]) {
        var seen = Set<MediaControlButton>()
        let kept = slots.prefix(Self.slotCount).map { button -> MediaControlButton in
            guard button != .none else { return .none }
            return seen.insert(button).inserted ? button : .none
        }
        self.slots = kept + Array(repeating: .none, count: Self.slotCount - kept.count)
    }

    var left: [MediaControlButton] { Array(slots[0..<Self.slotCount / 2]) }
    var right: [MediaControlButton] { Array(slots[Self.slotCount / 2..<Self.slotCount]) }

    /// `button` in `slot`, and out of the slot it had, so that choosing a button moves it.
    func setting(_ button: MediaControlButton, at slot: Int) -> MediaControlLayout {
        guard slots.indices.contains(slot) else { return self }
        var changed = slots
        if button != .none {
            for index in changed.indices where changed[index] == button { changed[index] = .none }
        }
        changed[slot] = button
        return MediaControlLayout(slots: changed)
    }

    /// Stored as the names of the buttons. A name this version does not know is no button; a value that is not a list of
    /// names is an error, which the settings answer with the default.
    init(from decoder: any Decoder) throws {
        let names = try decoder.singleValueContainer().decode([String].self)
        self.init(slots: names.map { MediaControlButton(rawValue: $0) ?? .none })
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(slots.map(\.rawValue))
    }
}

/// What a button's look and its action depend on, gathered by whoever draws or presses it.
nonisolated struct MediaControlContext {
    var state: NowPlayingState
    /// A source of lyrics is on, so there is a lyric row to show or hide.
    var lyricsAreOn: Bool
    var lyricsHidden: Bool
    /// The source can send a like (`NowPlayingSource.canLike`).
    var canLike: Bool
    /// The default output device has a volume that can be set.
    var hasVolume: Bool
    var volumeIsOpen: Bool
    /// Where the latest seek is going while the player has not reported it yet: the next seek starts from there, so quick
    /// taps add up.
    var pendingSeek: Double?
}

/// How a button is drawn: an SF Symbol, the words for the tooltip and for VoiceOver, whether it can be used, and whether it
/// is switched on (shuffle on, a liked track, lyrics shown, the volume slider open).
nonisolated struct MediaControlLook: Equatable {
    var symbol: String
    var label: String
    var isEnabled: Bool
    var isActive: Bool
}

/// What a press asks of the module. The volume slider opens in the row and asks nothing of the player.
nonisolated enum MediaControlEffect: Equatable {
    case command(MediaCommand)
    case seek(toSeconds: Double)
    case shuffle(ShuffleMode)
    case repeatMode(RepeatMode)
    case toggleLyrics
}

nonisolated extension MediaControlButton {
    func look(in context: MediaControlContext) -> MediaControlLook {
        let state = context.state
        let reason = unavailableReason(in: context)
        let isEnabled = reason == nil
        // The tooltip is the only place that can say why a button is faded.
        func label(_ usable: String) -> String { reason.map { "\(title): \($0)" } ?? usable }
        switch self {
        case .previous:
            return MediaControlLook(symbol: "backward.fill", label: label(title), isEnabled: isEnabled, isActive: false)
        case .next:
            return MediaControlLook(symbol: "forward.fill", label: label(title), isEnabled: isEnabled, isActive: false)
        case .rewind:
            return MediaControlLook(symbol: "gobackward.15", label: label(title), isEnabled: isEnabled, isActive: false)
        case .forward:
            return MediaControlLook(symbol: "goforward.15", label: label(title), isEnabled: isEnabled, isActive: false)
        case .shuffle:
            let isOn = state.shuffleMode?.isOn ?? false
            return MediaControlLook(symbol: "shuffle", label: label("\(title): \(isOn ? "bật" : "tắt")"), isEnabled: isEnabled, isActive: isOn)
        case .repeatMode:
            let mode = state.repeatMode ?? .off
            let (symbol, words): (String, String) = switch mode {
            case .off: ("repeat", "tắt")
            case .playlist: ("repeat", "tất cả")
            case .track: ("repeat.1", "một bài")
            }
            return MediaControlLook(symbol: symbol, label: label("\(title): \(words)"), isEnabled: isEnabled, isActive: mode != .off)
        case .like:
            return MediaControlLook(
                symbol: state.isLiked ? "heart.fill" : "heart", label: label(state.isLiked ? "Bỏ thích" : title),
                isEnabled: isEnabled, isActive: state.isLiked
            )
        case .volume:
            return MediaControlLook(symbol: "speaker.wave.2.fill", label: label(title), isEnabled: isEnabled, isActive: context.volumeIsOpen)
        case .lyrics:
            let isShown = !context.lyricsHidden
            return MediaControlLook(
                symbol: isShown ? "quote.bubble.fill" : "quote.bubble", label: label("\(title): \(isShown ? "hiện" : "ẩn")"),
                isEnabled: isEnabled, isActive: isEnabled && isShown
            )
        case .none:
            return MediaControlLook(symbol: "", label: title, isEnabled: false, isActive: false)
        }
    }

    /// Why the button cannot be used with what plays now; nil when it can.
    private func unavailableReason(in context: MediaControlContext) -> String? {
        let state = context.state
        switch self {
        case .previous, .next:
            // A browser's skip may go to the extension, which presses the page's own button, so its flag does not apply there.
            return !state.prohibitsSkip || state.isFromBrowser ? nil : "trình phát không cho phép"
        case .rewind, .forward:
            // Like the progress bar, a seek needs to know where the track is and how long it is.
            return state.elapsedAnchor != nil && state.durationSeconds != nil ? nil : "chưa biết vị trí và độ dài"
        case .shuffle:
            return state.shuffleMode == nil ? "trình phát không hỗ trợ" : nil
        case .repeatMode:
            return state.repeatMode == nil ? "trình phát không hỗ trợ" : nil
        case .like:
            if !state.supportsIsLiked { return "trình phát không hỗ trợ" }
            return context.canLike ? nil : "adapter chưa hỗ trợ"
        case .volume:
            return context.hasVolume ? nil : "thiết bị phát hiện tại không chỉnh được âm lượng"
        case .lyrics:
            return context.lyricsAreOn ? nil : "bật nguồn lời trong Cài đặt"
        case .none:
            return nil
        }
    }

    /// Whether the row draws it. A like the source cannot send is drawn as an empty slot, whatever was stored.
    func isDrawn(in context: MediaControlContext) -> Bool {
        switch self {
        case .none: false
        case .like: context.canLike
        default: true
        }
    }

    /// What pressing it asks of the module at `now`; nil when it cannot be used, and for the volume, which the row handles.
    func effect(in context: MediaControlContext, at now: Date) -> MediaControlEffect? {
        guard look(in: context).isEnabled else { return nil }
        let state = context.state
        switch self {
        case .previous: return .command(.previousTrack)
        case .next: return .command(.nextTrack)
        case .rewind: return seekTarget(context, by: -Self.seekStep, at: now).map { .seek(toSeconds: $0) }
        case .forward: return seekTarget(context, by: Self.seekStep, at: now).map { .seek(toSeconds: $0) }
        case .shuffle: return state.shuffleMode.map { .shuffle($0.toggled) }
        case .repeatMode: return state.repeatMode.map { .repeatMode($0.next) }
        case .like: return .command(.likeTrack)
        case .lyrics: return .toggleLyrics
        case .volume, .none: return nil
        }
    }

    /// `delta` seconds from the seek still on its way or else from where the playback clock puts the track at `now`, kept
    /// inside the track.
    private func seekTarget(_ context: MediaControlContext, by delta: Double, at now: Date) -> Double? {
        let state = context.state
        guard let duration = state.durationSeconds, let position = context.pendingSeek ?? PlaybackClock.position(state, at: now) else { return nil }
        return min(max(position + delta, 0), duration)
    }
}
