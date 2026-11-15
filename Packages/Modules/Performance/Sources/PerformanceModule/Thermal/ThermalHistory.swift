import Foundation

/// The SoC temperature over the last two minutes, for the sparkline. Samples carry their time, so a tab that was closed for a
/// while does not join old points to new ones.
nonisolated struct ThermalHistory: Equatable, Sendable {
    struct Sample: Equatable, Sendable {
        let date: Date
        let value: Double
    }

    /// How far back the sparkline goes.
    static let window: TimeInterval = 120
    /// The least height the sparkline's scale has, in degrees, so a steady temperature is a flat line and not noise stretched
    /// to the whole height.
    static let minimumSpan = 10.0

    private(set) var samples: [Sample] = []

    mutating func append(_ value: Double, at date: Date) {
        if let newest = samples.last, date < newest.date { samples.removeAll() }   // the clock went back
        samples.append(Sample(date: date, value: value))
        samples.removeAll { date.timeIntervalSince($0.date) > Self.window }
    }

    mutating func removeAll() {
        samples.removeAll()
    }

    /// The samples in stretches with no gap longer than `maxGap` between neighbours: one line each, so nothing is drawn across
    /// a pause.
    func runs(maxGap: TimeInterval) -> [[Sample]] {
        var runs: [[Sample]] = []
        for sample in samples {
            if let last = runs.last?.last, sample.date.timeIntervalSince(last.date) <= maxGap {
                runs[runs.count - 1].append(sample)
            } else {
                runs.append([sample])
            }
        }
        return runs
    }

    /// Where a sample goes across the sparkline, 0 (two minutes before the newest) to 1 (the newest, at the right edge).
    func position(of sample: Sample) -> Double {
        guard let newest = samples.last else { return 1 }
        return 1 - newest.date.timeIntervalSince(sample.date) / Self.window
    }

    /// The temperatures the sparkline's height stands for: the values, widened evenly to at least `minimumSpan`. Nil when empty.
    var scale: ClosedRange<Double>? {
        guard let low = samples.map(\.value).min(), let high = samples.map(\.value).max() else { return nil }
        let pad = max(Self.minimumSpan - (high - low), 0) / 2
        return (low - pad)...(high + pad)
    }
}
