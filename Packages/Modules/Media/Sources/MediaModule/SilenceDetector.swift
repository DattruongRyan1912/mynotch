import Foundation

/// Notices a system audio tap that hears nothing. macOS hands a tap zeros when the user denied
/// "System Audio Recording Only" and offers no API to ask, so long silence while music plays is the only sign.
nonisolated struct SilenceDetector {
    /// Silence must last longer than this: real tracks have quiet gaps, but not this long.
    static let limit: TimeInterval = 10
    /// A denied tap delivers exact zeros; real music never stays this low (−120 dBFS).
    static let silentPeak: Float = 1e-6

    private(set) var isLikelyDenied = false
    private var silentSince: TimeInterval?

    /// Feeds the loudest new sample (nil when no samples arrived) at `now` in seconds; returns the new
    /// verdict when it changes, nil otherwise.
    @discardableResult
    mutating func update(peak: Float?, at now: TimeInterval) -> Bool? {
        if let peak, peak > Self.silentPeak {
            silentSince = nil
        } else if silentSince == nil {
            silentSince = now
        }
        let denied = silentSince.map { now - $0 > Self.limit } ?? false
        guard denied != isLikelyDenied else { return nil }
        isLikelyDenied = denied
        return denied
    }
}
