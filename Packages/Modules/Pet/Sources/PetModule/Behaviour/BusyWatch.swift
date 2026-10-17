import Foundation

/// How busy this Mac usually is, and whether it is busy now by its own standards. A Mac that is busy all day is not a Mac that is busy:
/// the cat runs for its life only when the load is clearly above what this Mac does most of the time, and not for long.
///
/// A value that reads nothing and holds no timer: it is given the load once a second (while the cat is on the notch) and the time, and
/// says whether a burst is on. The Mac's usual load is the median of the last twelve minutes of what it was given, which a spike of a few
/// seconds does not move. A burst begins when the load has been over that by `margin` (and over `floor`, whatever the usual) for `hold`
/// seconds, lasts `longestBurst` seconds at the most, and begins no sooner than `cooldown` seconds after the one before it began.
nonisolated struct BusyWatch: Sendable {
    /// How far back the Mac's usual load looks, in seconds.
    static let window: TimeInterval = 12 * 60
    /// How many samples it takes to know a Mac's usual load: before that nothing is a spike, and a Mac the cat has only just met is neither
    /// busy nor quiet.
    static let minimumSamples = 60
    /// How far over the usual load, in shares of the processors, a spike is, and the load below which none is, whatever the usual.
    static let margin = 0.25
    static let floor = 0.7
    /// How long a spike has to hold before it is a burst.
    static let hold: TimeInterval = 10
    /// The least time from the start of one burst to the start of the next.
    static let cooldown: TimeInterval = 5 * 60
    /// The most a burst lasts.
    static let longestBurst: TimeInterval = 18
    /// A burst is over, before its time, when the load is back under the usual by this, or under the lower floor.
    static let easedMargin = 0.1
    static let easedFloor = 0.5
    /// More than this between two samples is time the cat was not there: a spike does not hold through it.
    static let longestGap: TimeInterval = 5

    private struct Sample {
        var at: TimeInterval
        var percent: Int
    }

    private var samples: [Sample] = []
    /// Where the samples that are still in the window begin; the ones before it have aged out.
    private var first = 0
    /// How many samples there are of each whole percent, which is what makes the median a scan of a hundred numbers.
    private var counts = [Int](repeating: 0, count: 101)
    private var lastSampleAt: TimeInterval?
    private var spikeSince: TimeInterval?
    private var burstStart: TimeInterval?
    private var lastBurstStart = -TimeInterval.infinity

    /// The median load of the last twelve minutes, nil until there are enough samples to say.
    var usual: Double? {
        let total = samples.count - first
        guard total >= Self.minimumSamples else { return nil }
        let middle = (total + 1) / 2
        var seen = 0
        for (percent, count) in counts.enumerated() {
            seen += count
            if seen >= middle { return Double(percent) / 100 }
        }
        return nil
    }

    /// Whether a burst is on at `now`.
    func isBursting(at now: TimeInterval) -> Bool {
        guard let burstStart else { return false }
        return now - burstStart < Self.longestBurst
    }

    /// How busy the Mac was over the second that ended at `now`, 0 to 1.
    mutating func record(_ load: Double, at now: TimeInterval) {
        if let lastSampleAt, now - lastSampleAt > Self.longestGap {
            spikeSince = nil
            burstStart = nil
        }
        lastSampleAt = now
        let percent = Int((min(max(load, 0), 1) * 100).rounded())
        samples.append(Sample(at: now, percent: percent))
        counts[percent] += 1
        age(at: now)

        guard let usual else {
            spikeSince = nil
            burstStart = nil
            return
        }
        if burstStart != nil {
            if load < max(usual + Self.easedMargin, Self.easedFloor) {
                // Back to normal: over, before its time.
                burstStart = nil
                spikeSince = nil
            } else if !isBursting(at: now) {
                burstStart = nil
            }
        } else if load >= max(usual + Self.margin, Self.floor) {
            spikeSince = spikeSince ?? now
        } else {
            spikeSince = nil
        }
        if burstStart == nil, let spikeSince, now - spikeSince >= Self.hold, now - lastBurstStart >= Self.cooldown {
            burstStart = now
            lastBurstStart = now
        }
    }

    /// The cat is back after being away: what was holding, and a burst that was on, are over. When the last burst began is not forgotten,
    /// or the cat would run every time another activity took the notch and gave it back; the samples age out by themselves.
    mutating func resume() {
        spikeSince = nil
        burstStart = nil
        lastSampleAt = nil
    }

    /// Forgets the samples that are older than the window.
    private mutating func age(at now: TimeInterval) {
        while first < samples.count, now - samples[first].at > Self.window {
            counts[samples[first].percent] -= 1
            first += 1
        }
        if first > 1024 {
            samples.removeFirst(first)
            first = 0
        }
    }
}
