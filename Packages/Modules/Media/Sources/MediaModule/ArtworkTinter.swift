import Foundation

/// What a tint was made for: one track's cover. Two tracks that share a cover have a tint each, and a track whose cover
/// changes (a player that sends a placeholder first) is a new entry, which is why the cover's bytes are part of it.
nonisolated struct ArtworkTintKey: Hashable, Sendable {
    var track: TrackIdentity
    /// Stands for the cover's bytes. The cover's `revision` is not used: it counts per run, so a track played again would
    /// never find its entry.
    var fingerprint: Int

    init(track: TrackIdentity, fingerprint: Int) {
        self.track = track
        self.fingerprint = fingerprint
    }

    init(track: TrackIdentity, artwork: ArtworkData) {
        var hasher = Hasher()
        hasher.combine(artwork.data)
        self.init(track: track, fingerprint: hasher.finalize())
    }
}

/// The tints of the last tracks, so that a track played again is tinted at once. Least recently used goes first.
nonisolated struct ArtworkTintCache {
    private let capacity: Int
    private var palettes: [ArtworkTintKey: ArtworkPalette] = [:]
    /// Least recently used first.
    private var order: [ArtworkTintKey] = []

    init(capacity: Int = 32) {
        self.capacity = max(capacity, 1)
    }

    var count: Int { palettes.count }

    mutating func palette(for key: ArtworkTintKey) -> ArtworkPalette? {
        guard let palette = palettes[key] else { return nil }
        touch(key)
        return palette
    }

    mutating func store(_ palette: ArtworkPalette, for key: ArtworkTintKey) {
        palettes[key] = palette
        touch(key)
        while order.count > capacity { palettes[order.removeFirst()] = nil }
    }

    private mutating func touch(_ key: ArtworkTintKey) {
        if let index = order.firstIndex(of: key) { order.remove(at: index) }
        order.append(key)
    }
}

/// Finds the tint of what plays, once per track: the colours are worked out on a background task, kept by track, and handed
/// to `show` on the main actor. A track that was tinted before comes back at once, from the cache.
final class ArtworkTinter {
    /// Works out a tint from the bytes of a cover, off the main actor.
    typealias Extract = @Sendable (Data) async -> ArtworkPalette?

    static let backgroundExtract: Extract = { data in
        await Task.detached(priority: .utility) { ArtworkColorExtractor.palette(imageData: data) }.value
    }

    private let extract: Extract
    private let show: (ArtworkPalette?) -> Void
    private var cache: ArtworkTintCache
    /// What was asked for last, so that the many updates of one track cost a comparison and not a hash of the cover.
    private var lastInput: (track: TrackIdentity, revision: Int?)?
    /// The track the tint on its way is for; an answer for another one is only kept.
    private var current: ArtworkTintKey?

    init(capacity: Int = 32, extract: @escaping Extract = ArtworkTinter.backgroundExtract, show: @escaping (ArtworkPalette?) -> Void) {
        cache = ArtworkTintCache(capacity: capacity)
        self.extract = extract
        self.show = show
    }

    /// Called with what plays, as often as it changes. A track without a cover has no tint; a track whose tint is not known
    /// keeps showing the last one until it is, so a track change does not flash.
    func update(track: TrackIdentity, artwork: ArtworkData?) {
        guard lastInput?.track != track || lastInput?.revision != artwork?.revision else { return }
        lastInput = (track, artwork?.revision)
        guard let artwork else {
            current = nil
            show(nil)
            return
        }
        let key = ArtworkTintKey(track: track, artwork: artwork)
        current = key
        if let palette = cache.palette(for: key) {
            show(palette)
            return
        }
        let data = artwork.data
        Task { [weak self, extract] in
            let palette = await extract(data)
            self?.finished(palette, for: key)
        }
    }

    /// Forgets what is on its way, and what was asked for last; what is in the cache stays.
    func stop() {
        current = nil
        lastInput = nil
    }

    private func finished(_ palette: ArtworkPalette?, for key: ArtworkTintKey) {
        if let palette { cache.store(palette, for: key) }
        guard key == current else { return }
        show(palette)
    }
}
