import Foundation

nonisolated struct DownloadEvent: Equatable, Sendable {
    var url: URL
    var name: String
}

/// Decides when a file in Downloads has finished downloading. Pure: fed observations and clock ticks.
///
/// A path becomes a candidate when a browser's partial marker (`.download` bundle, `.crdownload`, `.part`)
/// was seen for it, or when it carries a download origin attribute. A plain file copied in has neither, so it
/// never counts; an origin-only file must also have been modified in the last few seconds, or an old
/// quarantined file touched by Gatekeeper or a rename would look like a download. A candidate completes once no marker is present, it is not empty, and its size has been
/// stable for a second and nothing was observed for a short while.
nonisolated struct DownloadCompletionRule {
    static let partialExtensions: Set<String> = ["download", "crdownload", "part"]

    private struct Candidate {
        var size: Int64
        var startedAt: Date
        var sizeChangedAt: Date
        var observedAt: Date
    }

    /// How recent an origin-only file's date must be to start a candidate.
    private static let freshFor: TimeInterval = 10
    /// A candidate that has not completed by then (an empty file with an origin, say) is dropped.
    private static let giveUpAfter: TimeInterval = 600
    /// How long `hadPartial` and `completed` remember a path.
    private static let rememberFor: TimeInterval = 3_600

    private let stableFor: TimeInterval
    private let debounce: TimeInterval
    private var partials: Set<String> = []
    /// Final paths a partial marker was seen for, which stays true after the marker disappears.
    private var hadPartial: [String: Date] = [:]
    private var candidates: [String: Candidate] = [:]
    private var completed: [String: Date] = [:]

    init(stableFor: TimeInterval = 1, debounce: TimeInterval = 0.3) {
        self.stableFor = stableFor
        self.debounce = debounce
    }

    /// Whether `tick(now:)` still has something to wait for.
    var hasPending: Bool { !candidates.isEmpty }

    mutating func observe(_ observation: FileObservation, now: Date) {
        forget(now: now)
        let url = URL(fileURLWithPath: observation.path)
        let name = url.lastPathComponent
        guard !name.hasPrefix(".") else { return }
        let removed = observation.flags.contains(.removed)

        if Self.partialExtensions.contains(url.pathExtension) {
            let final = url.deletingPathExtension().path
            // Only `.download` is a bundle; a directory with the other extensions is not a download.
            guard !observation.isDirectory || url.pathExtension == "download" else { return }
            if removed {
                partials.remove(final)
                candidates[final]?.sizeChangedAt = now
            } else {
                partials.insert(final)
                hadPartial[final] = now
                completed[final] = nil
            }
            return
        }

        guard !observation.isDirectory else { return }
        let path = observation.path
        if removed {
            candidates[path] = nil
            hadPartial[path] = nil
            completed[path] = nil
            return
        }
        guard completed[path] == nil else { return }
        if var candidate = candidates[path] {
            if candidate.size != observation.size { candidate.sizeChangedAt = now }
            candidate.size = observation.size
            candidate.observedAt = now
            candidates[path] = candidate
        } else if hadPartial[path] != nil || (observation.hasOrigin && abs(now.timeIntervalSince(observation.date)) <= Self.freshFor) {
            candidates[path] = Candidate(size: observation.size, startedAt: now, sizeChangedAt: now, observedAt: now)
        }
    }

    /// Returns the downloads that finished by `now`, each once.
    mutating func tick(now: Date) -> [DownloadEvent] {
        forget(now: now)
        let ready = candidates.filter { path, candidate in
            candidate.size > 0 && !partials.contains(path)
                && now.timeIntervalSince(candidate.sizeChangedAt) >= stableFor
                && now.timeIntervalSince(candidate.observedAt) >= debounce
        }
        return ready.keys.sorted().map { path in
            candidates[path] = nil
            hadPartial[path] = nil
            completed[path] = now
            let url = URL(fileURLWithPath: path)
            return DownloadEvent(url: url, name: url.lastPathComponent)
        }
    }

    private mutating func forget(now: Date) {
        candidates = candidates.filter { now.timeIntervalSince($1.startedAt) < Self.giveUpAfter }
        completed = completed.filter { now.timeIntervalSince($1) < Self.rememberFor }
        // A marker still on disk keeps its path, however long the download takes.
        hadPartial = hadPartial.filter { partials.contains($0) || now.timeIntervalSince($1) < Self.rememberFor }
    }
}
