import AVFoundation
import Observation

/// What the editor needs of the player that shows the preview, so its tests play nothing and make no sound.
protocol PreviewPlaying: AnyObject {
    /// Where the player is, in seconds of the edited video.
    var editedTime: TimeInterval { get }
    var isPlaying: Bool { get }
    /// Shows `item` from `editedTime`, going on playing if it was playing.
    func load(_ item: AVPlayerItem, at editedTime: TimeInterval)
    func seek(toEdited time: TimeInterval)
    func play()
    func pause()
}

/// The real player, on `AVPlayer`. Its time is kept up to date thirty times a second for the playhead.
@Observable final class RecordingPlayer: PreviewPlaying {
    let player = AVPlayer()
    private(set) var editedTime = 0.0
    private(set) var isPlaying = false
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, time.isValid, time.isNumeric else { return }
                self.editedTime = time.seconds
                self.isPlaying = self.player.rate != 0
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isPlaying = false }
        }
    }

    isolated deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        player.pause()
    }

    func load(_ item: AVPlayerItem, at editedTime: TimeInterval) {
        let wasPlaying = isPlaying
        player.replaceCurrentItem(with: item)
        seek(toEdited: editedTime)
        if wasPlaying { player.play() }
    }

    func seek(toEdited time: TimeInterval) {
        editedTime = time
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func play() {
        // At the end, play starts over.
        if let duration = player.currentItem?.duration.seconds, duration.isFinite, editedTime >= duration - 0.05 { seek(toEdited: 0) }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }
}
