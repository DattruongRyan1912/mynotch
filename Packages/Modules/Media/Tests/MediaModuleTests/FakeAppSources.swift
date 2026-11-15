import Foundation
@testable import MediaModule

/// Stands in for Music or Spotify read by Apple Events: tests script what a read says and read back what was asked, and no
/// Apple Event is ever sent to a real app.
final class FakeAppPlayerControl: AppPlayerControl {
    let player: KnownPlayer
    /// What the reads say, one after the other; the last one is said again.
    var readings: [AppPlayerReading] = [.stopped]
    var outcome = AppPlayerOutcome.done
    /// A read waits for this before it answers, so that a test can keep one on its way.
    var gate: (@MainActor () async -> Void)?
    private(set) var readCount = 0
    private(set) var performed: [AppPlayerCommand] = []

    init(_ player: KnownPlayer) {
        self.player = player
    }

    func read() async -> AppPlayerReading {
        readCount += 1
        let index = min(readCount - 1, readings.count - 1)
        let answer = readings[index]
        await gate?()
        return answer
    }

    func perform(_ command: AppPlayerCommand) async -> AppPlayerOutcome {
        performed.append(command)
        return outcome
    }
}

/// The machine, for the hub: the notifications the players post, apps quitting and which apps run.
final class FakeAppEnvironment {
    var running: Set<String> = []
    private var observers: [String: [Int: @MainActor ([AnyHashable: Any]) -> Void]] = [:]
    private var quitObservers: [Int: @MainActor (String) -> Void] = [:]
    private var next = 0

    var observedNames: [String] { observers.filter { !$0.value.isEmpty }.keys.sorted() }
    var observerCount: Int { observers.values.reduce(0) { $0 + $1.count } + quitObservers.count }

    var environment: MediaAppEnvironment {
        MediaAppEnvironment(
            observe: { [unowned self] name, handler in
                let id = nextID()
                observers[name, default: [:]][id] = handler
                return { [weak self] in self?.observers[name]?[id] = nil }
            },
            observeQuit: { [unowned self] handler in
                let id = nextID()
                quitObservers[id] = handler
                return { [weak self] in self?.quitObservers[id] = nil }
            },
            isRunning: { [unowned self] in running.contains($0) }
        )
    }

    private func nextID() -> Int {
        next += 1
        return next
    }

    /// The player posts its notification, as Music and Spotify do when something changes.
    func post(_ player: KnownPlayer, _ info: [AnyHashable: Any]) {
        for handler in observers[player.notificationName]?.values ?? [:].values { handler(info) }
    }

    /// Music says what it plays.
    func music(_ state: String = "Playing", name: String = "Song", artist: String? = "Artist", album: String? = "Album", totalTime: Int = 200_000, id: Int = 1) {
        var info: [AnyHashable: Any] = ["Player State": state, "Name": name, "Total Time": totalTime, "Persistent ID": id]
        info["Artist"] = artist
        info["Album"] = album
        post(.music, info)
        running.insert(KnownPlayer.music.bundleID)
    }

    /// Spotify says what it plays.
    func spotify(_ state: String = "Playing", name: String = "Track", artist: String? = "Singer", duration: Int = 180_000, position: Double? = 12.5, id: String = "spotify:track:1") {
        var info: [AnyHashable: Any] = ["Player State": state, "Name": name, "Duration": duration, "Track ID": id]
        info["Artist"] = artist
        info["Playback Position"] = position
        post(.spotify, info)
        running.insert(KnownPlayer.spotify.bundleID)
    }

    func quit(_ bundleID: String) {
        running.remove(bundleID)
        for handler in quitObservers.values { handler(bundleID) }
    }
}

/// A script runner that answers from a table and records what it was asked.
final class FakePlayerScriptRunner: PlayerScriptRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [PlayerScriptResult]
    private var asked: [String] = []

    init(_ answers: [PlayerScriptResult] = [.failed]) {
        self.answers = answers
    }

    var scripts: [String] { lock.withLock { asked } }

    func run(_ source: String) async -> PlayerScriptResult {
        lock.withLock {
            asked.append(source)
            return answers.count > 1 ? answers.removeFirst() : answers[0]
        }
    }
}
