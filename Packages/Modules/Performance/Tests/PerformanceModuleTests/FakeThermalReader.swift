import MyNotchCore
@testable import PerformanceModule

/// A reader that answers with what the test set, counts how often it was asked, and can hold an answer back so a test can
/// act while a read is in flight.
actor FakeThermalReader: ThermalReading {
    private(set) var reads = 0
    private(set) var shutdowns = 0
    private let available: Bool
    private var snapshot: ThermalSnapshot?
    private var isHolding = false
    private var held: [CheckedContinuation<Void, Never>] = []

    init(_ snapshot: ThermalSnapshot? = FakeThermalReader.warm, available: Bool = true) {
        self.snapshot = snapshot
        self.available = available
    }

    static let warm = ThermalSnapshot(
        cpu: 78, gpu: 66, fans: [FanReading(index: 0, rpm: 3200, minRPM: 1200, maxRPM: 5779)]
    )

    func answer(with snapshot: ThermalSnapshot?) { self.snapshot = snapshot }

    /// Reads from now on wait until `release()`.
    func hold() { isHolding = true }

    func release() {
        isHolding = false
        held.forEach { $0.resume() }
        held.removeAll()
    }

    func isAvailable() async -> Bool { available }

    func read() async -> ThermalSnapshot? {
        reads += 1
        if isHolding { await withCheckedContinuation { held.append($0) } }
        return snapshot
    }

    func shutdown() { shutdowns += 1 }
}

/// Lets the main actor's pending work and the reader's answers go through: reads hop to the reader and back, so a test waits for
/// what it expects instead of assuming a number of turns.
@MainActor func settle(_ condition: () async -> Bool) async {
    for _ in 0..<2_000 {
        if await condition() { return }
        await Task.yield()
    }
}

/// Gives anything that is going to happen a chance to, for a test that expects nothing to.
@MainActor func idle() async {
    for _ in 0..<200 { await Task.yield() }
}
