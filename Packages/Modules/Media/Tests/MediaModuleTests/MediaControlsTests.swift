import AppKit
import Foundation
import Testing
@testable import MediaModule

/// Which buttons the row has and where: stored, normalised, and edited a slot at a time.
@Suite struct MediaControlLayoutTests {
    @Test func theDefaultKeepsTodaysLookPreviousAndNextBesideTheCentre() {
        let standard = MediaControlLayout.standard
        #expect(standard.slots == [.none, .previous, .next, .none])
        #expect(standard.left == [.none, .previous])
        #expect(standard.right == [.next, .none])
        #expect(MediaControlLayout.slotCount == 4, "two on each side of play and pause: five buttons at most")
    }

    @Test func theChoicesAreTheBriefsInOrderWithNoneLast() {
        #expect(MediaControlButton.allCases.map(\.title) == [
            "Bài trước", "Bài tiếp theo", "Tua lùi 15 giây", "Tua tới 15 giây", "Phát ngẫu nhiên",
            "Lặp lại", "Thích", "Âm lượng", "Lời bài hát", "Không có",
        ])
    }

    @Test func aLayoutIsStoredAsTheNamesOfItsButtons() throws {
        let json = try JSONEncoder().encode(MediaControlLayout.standard)
        #expect(String(decoding: json, as: UTF8.self) == #"["none","previous","next","none"]"#)
        let all = MediaControlLayout(slots: [.shuffle, .repeatMode, .volume, .lyrics])
        #expect(String(decoding: try JSONEncoder().encode(all), as: UTF8.self) == #"["shuffle","repeat","volume","lyrics"]"#)
        #expect(try JSONDecoder().decode(MediaControlLayout.self, from: JSONEncoder().encode(all)) == all)
        #expect(Set(MediaControlButton.allCases.map(\.rawValue)).count == MediaControlButton.allCases.count)
    }

    @Test func aNameThisVersionDoesNotKnowIsNoButtonAndTheLengthIsAlwaysFour() throws {
        let decode = { (json: String) throws -> MediaControlLayout in try JSONDecoder().decode(MediaControlLayout.self, from: Data(json.utf8)) }
        #expect(try decode(#"["next","from-the-future","previous","none"]"#).slots == [.next, .none, .previous, .none])
        #expect(try decode(#"["next"]"#).slots == [.next, .none, .none, .none])
        #expect(try decode(#"[]"#).slots == [.none, .none, .none, .none])
        #expect(try decode(#"["next","previous","shuffle","repeat","like","volume"]"#).slots == [.next, .previous, .shuffle, .repeatMode])
        #expect(throws: DecodingError.self) { try decode(#"{"slots":[]}"#) }
    }

    @Test func aButtonUsedTwiceStaysInItsFirstSlot() {
        #expect(MediaControlLayout(slots: [.next, .previous, .next, .volume]).slots == [.next, .previous, .none, .volume])
        #expect(MediaControlLayout(slots: [.none, .none, .none, .none]).slots == [.none, .none, .none, .none], "none may repeat")
    }

    @Test func choosingAButtonPutsItInTheSlotAndTakesItOutOfItsOldOne() {
        let moved = MediaControlLayout.standard.setting(.next, at: 0)
        #expect(moved.slots == [.next, .previous, .none, .none])
        #expect(MediaControlLayout.standard.setting(.shuffle, at: 3).slots == [.none, .previous, .next, .shuffle])
        #expect(MediaControlLayout.standard.setting(.none, at: 2).slots == [.none, .previous, .none, .none])
        #expect(MediaControlLayout.standard.setting(.previous, at: 1) == .standard)
    }

    @Test func aSlotThatDoesNotExistChangesNothing() {
        #expect(MediaControlLayout.standard.setting(.volume, at: 4) == .standard)
        #expect(MediaControlLayout.standard.setting(.volume, at: -1) == .standard)
    }
}

/// What each button looks like for what plays, whether it can be used, and what it does.
@Suite struct MediaControlButtonTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func state(
        bundle: String = "com.example.Player", playing: Bool = true, elapsed: Double? = 100, duration: Double? = 200,
        shuffle: ShuffleMode? = nil, repeatMode: RepeatMode? = nil,
        liked: Bool = false, supportsLike: Bool = false, prohibitsSkip: Bool = false
    ) -> NowPlayingState {
        NowPlayingState(
            bundleIdentifier: bundle, title: "Song", durationSeconds: duration,
            elapsedAnchor: elapsed.map { PlaybackAnchor(elapsedSeconds: $0, timestamp: now, rate: playing ? 1 : 0) },
            isPlaying: playing, shuffleMode: shuffle, repeatMode: repeatMode,
            isLiked: liked, supportsIsLiked: supportsLike, prohibitsSkip: prohibitsSkip
        )
    }

    func context(
        _ state: NowPlayingState, lyricsAreOn: Bool = true, lyricsHidden: Bool = false, canLike: Bool = true,
        hasVolume: Bool = true, volumeIsOpen: Bool = false
    ) -> MediaControlContext {
        MediaControlContext(
            state: state, lyricsAreOn: lyricsAreOn, lyricsHidden: lyricsHidden, canLike: canLike,
            hasVolume: hasVolume, volumeIsOpen: volumeIsOpen
        )
    }

    func look(_ button: MediaControlButton, _ context: MediaControlContext) -> MediaControlLook { button.look(in: context) }

    func effect(_ button: MediaControlButton, _ context: MediaControlContext, after seconds: TimeInterval = 0) -> MediaControlEffect? {
        button.effect(in: context, at: now + seconds)
    }

    // MARK: skipping

    @Test func previousAndNextAreNeverDisabledByDefaultAndSendTheMediaRemoteCommands() {
        let plain = context(state())
        #expect(look(.previous, plain) == MediaControlLook(symbol: "backward.fill", label: "Bài trước", isEnabled: true, isActive: false))
        #expect(look(.next, plain) == MediaControlLook(symbol: "forward.fill", label: "Bài tiếp theo", isEnabled: true, isActive: false))
        #expect(effect(.previous, plain) == .command(.previousTrack))
        #expect(effect(.next, plain) == .command(.nextTrack))
    }

    @Test func aPlayerThatProhibitsSkippingHasTheSkipButtonsDisabled() {
        let locked = context(state(prohibitsSkip: true))
        #expect(!look(.previous, locked).isEnabled)
        #expect(!look(.next, locked).isEnabled)
        #expect(look(.next, locked).label == "Bài tiếp theo: trình phát không cho phép")
        #expect(effect(.previous, locked) == nil)
        #expect(effect(.next, locked) == nil)
        // The other buttons are not the skip's business.
        #expect(look(.rewind, locked).isEnabled)
    }

    @Test func aBrowsersSkipMayGoThroughTheExtensionSoTheFlagDoesNotDisableIt() {
        let video = context(state(bundle: "com.google.Chrome", prohibitsSkip: true))
        #expect(look(.next, video).isEnabled)
        #expect(effect(.next, video) == .command(.nextTrack), "the module's route decides: the extension or MediaRemote")
        let helper = context(NowPlayingState(
            bundleIdentifier: "com.google.Chrome.helper", parentApplicationBundleIdentifier: "com.google.Chrome", title: "Video", prohibitsSkip: true
        ))
        #expect(look(.previous, helper).isEnabled)
    }

    // MARK: seeking

    @Test func theSeekButtonsGoFifteenSecondsFromThePlaybackClock() {
        let plain = context(state(elapsed: 100))
        #expect(look(.rewind, plain) == MediaControlLook(symbol: "gobackward.15", label: "Tua lùi 15 giây", isEnabled: true, isActive: false))
        #expect(look(.forward, plain) == MediaControlLook(symbol: "goforward.15", label: "Tua tới 15 giây", isEnabled: true, isActive: false))
        #expect(effect(.rewind, plain) == .seek(toSeconds: 85))
        #expect(effect(.forward, plain) == .seek(toSeconds: 115))
        // The player reported 100 s at `now`; ten seconds later it is at 110 s.
        #expect(effect(.rewind, plain, after: 10) == .seek(toSeconds: 95))
        #expect(effect(.forward, plain, after: 10) == .seek(toSeconds: 125))
    }

    @Test func aPausedTrackSeeksFromWhereItStopped() {
        let paused = context(state(playing: false, elapsed: 100))
        #expect(effect(.forward, paused, after: 30) == .seek(toSeconds: 115))
        #expect(effect(.rewind, paused, after: 30) == .seek(toSeconds: 85))
    }

    @Test func seekTargetsStayInsideTheTrack() {
        #expect(effect(.rewind, context(state(elapsed: 10))) == .seek(toSeconds: 0))
        #expect(effect(.rewind, context(state(elapsed: 0))) == .seek(toSeconds: 0))
        #expect(effect(.forward, context(state(elapsed: 190, duration: 200))) == .seek(toSeconds: 200))
        #expect(effect(.forward, context(state(elapsed: 200, duration: 200))) == .seek(toSeconds: 200))
        // The clock is already held at the end by `PlaybackClock`; a seek never asks for more.
        #expect(effect(.forward, context(state(elapsed: 190, duration: 200)), after: 60) == .seek(toSeconds: 200))
    }

    @Test func seekingNeedsAKnownPositionAndLength() {
        for unseekable in [state(elapsed: nil), state(duration: nil), state(elapsed: nil, duration: nil)] {
            let live = context(unseekable)
            for button in [MediaControlButton.rewind, .forward] {
                #expect(!look(button, live).isEnabled, "\(button)")
                #expect(look(button, live).label.hasSuffix(": chưa biết vị trí và độ dài"), "\(button)")
                #expect(effect(button, live) == nil, "\(button)")
            }
        }
    }

    // MARK: shuffle and repeat

    @Test func shuffleShowsItsModeAndSetsTheOppositeOne() {
        let off = context(state(shuffle: .off))
        #expect(look(.shuffle, off) == MediaControlLook(symbol: "shuffle", label: "Phát ngẫu nhiên: tắt", isEnabled: true, isActive: false))
        #expect(effect(.shuffle, off) == .shuffle(.tracks))
        for mode in [ShuffleMode.tracks, .albums] {
            let on = context(state(shuffle: mode))
            #expect(look(.shuffle, on) == MediaControlLook(symbol: "shuffle", label: "Phát ngẫu nhiên: bật", isEnabled: true, isActive: true))
            #expect(effect(.shuffle, on) == .shuffle(.off))
        }
    }

    @Test func repeatShowsOffAllAndOneWithTheirOwnIconsAndCycles() {
        let off = context(state(repeatMode: .off))
        let all = context(state(repeatMode: .playlist))
        let one = context(state(repeatMode: .track))
        #expect(look(.repeatMode, off) == MediaControlLook(symbol: "repeat", label: "Lặp lại: tắt", isEnabled: true, isActive: false))
        #expect(look(.repeatMode, all) == MediaControlLook(symbol: "repeat", label: "Lặp lại: tất cả", isEnabled: true, isActive: true))
        #expect(look(.repeatMode, one) == MediaControlLook(symbol: "repeat.1", label: "Lặp lại: một bài", isEnabled: true, isActive: true))
        #expect(effect(.repeatMode, off) == .repeatMode(.playlist))
        #expect(effect(.repeatMode, all) == .repeatMode(.track))
        #expect(effect(.repeatMode, one) == .repeatMode(.off))
    }

    @Test func aPlayerThatReportsNoModeHasShuffleAndRepeatDisabled() {
        let silent = context(state())
        for button in [MediaControlButton.shuffle, .repeatMode] {
            #expect(!look(button, silent).isEnabled, "\(button)")
            #expect(!look(button, silent).isActive, "\(button)")
            #expect(look(button, silent).label.hasSuffix(": trình phát không hỗ trợ"), "\(button)")
            #expect(effect(button, silent) == nil, "\(button)")
        }
        // One mode does not enable the other.
        #expect(look(.shuffle, context(state(repeatMode: .off))).isEnabled == false)
        #expect(look(.repeatMode, context(state(shuffle: .off))).isEnabled == false)
    }

    // MARK: like

    @Test func likeNeedsAPlayerThatSupportsItAndASourceThatCanSendIt() {
        let supported = context(state(supportsLike: true))
        #expect(look(.like, supported) == MediaControlLook(symbol: "heart", label: "Thích", isEnabled: true, isActive: false))
        #expect(effect(.like, supported) == .command(.likeTrack))
        let unsupported = context(state(supportsLike: false))
        #expect(!look(.like, unsupported).isEnabled)
        #expect(look(.like, unsupported).label == "Thích: trình phát không hỗ trợ")
        #expect(effect(.like, unsupported) == nil)
        let blind = context(state(supportsLike: true), canLike: false)
        #expect(!look(.like, blind).isEnabled)
        #expect(look(.like, blind).label == "Thích: adapter chưa hỗ trợ")
        #expect(effect(.like, blind) == nil)
    }

    @Test func aLikedTrackShowsAFilledHeartAndOffersToUndo() {
        let liked = context(state(liked: true, supportsLike: true))
        #expect(look(.like, liked) == MediaControlLook(symbol: "heart.fill", label: "Bỏ thích", isEnabled: true, isActive: true))
        #expect(effect(.like, liked) == .command(.likeTrack), "the player toggles it")
    }

    // MARK: volume and lyrics

    @Test func volumeNeedsAnOutputDeviceThatHasOneAndIsDoneByTheViewNotTheModule() {
        let open = context(state(), volumeIsOpen: true)
        #expect(look(.volume, context(state())) == MediaControlLook(symbol: "speaker.wave.2.fill", label: "Âm lượng", isEnabled: true, isActive: false))
        #expect(look(.volume, open).isActive)
        #expect(!look(.volume, context(state(), hasVolume: false)).isEnabled)
        #expect(look(.volume, context(state(), hasVolume: false)).label == "Âm lượng: thiết bị phát hiện tại không chỉnh được âm lượng")
        #expect(effect(.volume, context(state())) == nil, "the slider opens in the row; nothing is sent to the player")
    }

    @Test func lyricsShowWhetherTheRowIsOnAndNeedASourceOfLyrics() {
        let shown = context(state())
        let hidden = context(state(), lyricsHidden: true)
        #expect(look(.lyrics, shown) == MediaControlLook(symbol: "quote.bubble.fill", label: "Lời bài hát: hiện", isEnabled: true, isActive: true))
        #expect(look(.lyrics, hidden) == MediaControlLook(symbol: "quote.bubble", label: "Lời bài hát: ẩn", isEnabled: true, isActive: false))
        #expect(effect(.lyrics, shown) == .toggleLyrics)
        #expect(effect(.lyrics, hidden) == .toggleLyrics)
        let off = context(state(), lyricsAreOn: false)
        #expect(!look(.lyrics, off).isEnabled)
        #expect(!look(.lyrics, off).isActive)
        #expect(look(.lyrics, off).label == "Lời bài hát: bật nguồn lời trong Cài đặt")
        #expect(effect(.lyrics, off) == nil)
    }

    @Test func noButtonIsNeverEnabledAndDoesNothing() {
        let plain = context(state(liked: true, supportsLike: true))
        #expect(!look(.none, plain).isEnabled)
        #expect(effect(.none, plain) == nil)
        #expect(look(.none, plain).label == "Không có")
    }

    @Test func everySymbolIsOneThatTheSystemHas() {
        let contexts = [
            context(state()),
            context(state(shuffle: .tracks, repeatMode: .track, liked: true, supportsLike: true), lyricsHidden: true, volumeIsOpen: true),
            context(state(repeatMode: .playlist)),
        ]
        for context in contexts {
            for button in MediaControlButton.allCases where button != .none {
                let symbol = look(button, context).symbol
                #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol)")
            }
        }
    }
}
