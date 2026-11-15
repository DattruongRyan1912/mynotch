import Foundation

/// One process and its CPU share: percentage of one core (e.g. 25.4%), comparable to Activity Monitor.
nonisolated struct ProcessCPU: Equatable, Identifiable, Sendable {
    let pid: Int32
    let name: String
    let percent: Double
    /// Where its executable is, so an app's helper can be shown with the app's icon.
    let path: String?

    var id: Int32 { pid }
}

/// What one read of system CPU returns.
nonisolated struct CPUSnapshot: Equatable, Sendable {
    /// Overall system CPU load percentage (0...100).
    var usagePercent: Double?
    /// Top CPU-consuming processes, sorted highest percentage first.
    var processes: [ProcessCPU]
}

/// Reads the CPU load of the Mac and its heaviest processes; faked in tests.
nonisolated protocol CPUReading: Sendable {
    func read(topProcesses: Int) async -> CPUSnapshot
}
