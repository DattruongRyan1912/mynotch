import Foundation

/// One read of a player app by Apple Events.
nonisolated enum AppPlayerReading: Equatable, Sendable {
    case snapshot(AppPlayerSnapshot)
    /// The app runs and has nothing loaded.
    case stopped
    case notRunning
    /// macOS did not let MyNotch send the app Apple Events (Automation).
    case notAllowed
    case failed
}

nonisolated enum AppPlayerCommand: Equatable, Sendable {
    case play
    case pause
    case togglePlayPause
    case next
    case previous
    case seek(seconds: Double)
}

nonisolated enum AppPlayerOutcome: Equatable, Sendable {
    case done
    case notRunning
    case notAllowed
    case failed
}

/// What the module asks of a player app besides what it learns from the app's notifications: where the player is and its cover
/// (`read`), and to do something (`perform`). Neither starts the app: they are only asked for an app that is running, and the scripts
/// check it again, since an app may quit between the two.
protocol AppPlayerControl: AnyObject {
    var player: KnownPlayer { get }
    func read() async -> AppPlayerReading
    func perform(_ command: AppPlayerCommand) async -> AppPlayerOutcome
}

/// What a script gives back, reduced to plain values (the descriptor it came in belongs to the queue that ran the script).
nonisolated enum PlayerScriptValue: Equatable, Sendable {
    case text(String)
    case number(Double)
    case data(Data)
    case list([PlayerScriptValue])
    /// `missing value`, or nothing.
    case missing
}

nonisolated enum PlayerScriptResult: Equatable, Sendable {
    case value(PlayerScriptValue)
    case notRunning
    case notAllowed
    case failed
}

/// Runs a script. A protocol so that tests give their own answers, and no test sends an Apple Event to a real app.
nonisolated protocol PlayerScriptRunner: Sendable {
    func run(_ source: String) async -> PlayerScriptResult
}

/// What a module made for a test has: it answers nothing and sends nothing.
nonisolated struct InertScriptRunner: PlayerScriptRunner {
    func run(_ source: String) async -> PlayerScriptResult { .failed }
}

/// The scripts. Each one is wrapped in a check that the app is running, which does not start it: a `tell` to an app that is not
/// running would.
nonisolated enum PlayerScripts {
    /// No track is longer than this many seconds.
    static let maxSeconds = 10_000_000.0

    /// The state, the track and the position in one go: `{state, name, artist, album, position, duration, id}` and, for Spotify,
    /// the address of the cover. `{"stopped"}` while nothing is loaded and `{"notrunning"}` when the app is not there.
    static func poll(_ player: KnownPlayer) -> String {
        switch player {
        case .music:
            return guarded(player, """
                if player state is stopped then return {"stopped"}
                set t to current track
                return {(player state as text), name of t, artist of t, album of t, player position, duration of t, (database ID of t) as text}
                """)
        case .spotify:
            return guarded(player, """
                if player state is stopped then return {"stopped"}
                set t to current track
                return {(player state as text), name of t, artist of t, album of t, player position, duration of t, id of t, artwork url of t}
                """)
        }
    }

    /// The cover of the current track as data, for the app that has it (Music); nil for the one that gives an address instead.
    static func artwork(_ player: KnownPlayer) -> String? {
        switch player {
        case .music:
            return guarded(player, """
                set t to current track
                if (count of artworks of t) is 0 then return missing value
                return data of artwork 1 of t
                """)
        case .spotify:
            return nil
        }
    }

    static func command(_ command: AppPlayerCommand, for player: KnownPlayer) -> String {
        let action = switch command {
        case .play: "play"
        case .pause: "pause"
        case .togglePlayPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        // A fixed three decimals with a point, whatever the Mac's region.
        case .seek(let seconds): "set player position to \(String(format: "%.3f", min(max(seconds, 0), maxSeconds)))"
        }
        return guarded(player, "\(action)\nreturn true")
    }

    private static func guarded(_ player: KnownPlayer, _ body: String) -> String {
        let indented = body.split(separator: "\n", omittingEmptySubsequences: false).map { "        " + $0 }.joined(separator: "\n")
        return """
            if application id "\(player.bundleID)" is running then
                tell application id "\(player.bundleID)"
            \(indented)
                end tell
            end if
            return {"notrunning"}
            """
    }
}

/// Music and Spotify through Apple Events. The cover is read once per track (Music's is data, Spotify's an address that is fetched),
/// never at the pace of the poll.
final class AppleScriptPlayerControl: AppPlayerControl {
    let player: KnownPlayer
    private let runner: any PlayerScriptRunner
    /// Fetches a cover from an address; nil for anything that is not a cover from the app's own service.
    private let fetchArtwork: (URL) async -> Data?
    private var cover: (key: String, data: Data?)?

    init(player: KnownPlayer, runner: any PlayerScriptRunner, fetchArtwork: @escaping (URL) async -> Data? = { _ in nil }) {
        self.player = player
        self.runner = runner
        self.fetchArtwork = fetchArtwork
    }

    func read() async -> AppPlayerReading {
        switch await runner.run(PlayerScripts.poll(player)) {
        case .notRunning: return .notRunning
        case .notAllowed: return .notAllowed
        case .failed: return .failed
        case .value(let value):
            guard var snapshot = parse(value) else {
                if case .list(let items) = value, case .text(let first)? = items.first {
                    return first == "stopped" ? .stopped : first == "notrunning" ? .notRunning : .failed
                }
                return .failed
            }
            snapshot.artwork = await artwork(for: snapshot)
            return .snapshot(snapshot)
        }
    }

    func perform(_ command: AppPlayerCommand) async -> AppPlayerOutcome {
        switch await runner.run(PlayerScripts.command(command, for: player)) {
        case .value(let value):
            if case .list(let items) = value, case .text("notrunning")? = items.first { return .notRunning }
            return .done
        case .notRunning: return .notRunning
        case .notAllowed: return .notAllowed
        case .failed: return .failed
        }
    }

    // MARK: reading

    /// `{state, name, artist, album, position, duration, id[, cover address]}` as a snapshot; nil for any other answer.
    func parse(_ value: PlayerScriptValue) -> AppPlayerSnapshot? {
        guard case .list(let items) = value, items.count >= 7, case .text(let state) = items[0] else { return nil }
        let lowered = state.lowercased()
        guard lowered == "playing" || lowered == "paused" || lowered == "fast forwarding" || lowered == "rewinding" else { return nil }
        guard let title = Self.text(items[1]), !title.isEmpty else { return nil }
        // Music's duration is in seconds, Spotify's in milliseconds.
        let duration = Self.number(items[5]).map { player == .spotify ? $0 / 1000 : $0 }
        return AppPlayerSnapshot(
            isPlaying: lowered != "paused", title: title, artist: Self.text(items[2]).flatMap { $0.isEmpty ? nil : $0 },
            album: Self.text(items[3]).flatMap { $0.isEmpty ? nil : $0 }, durationSeconds: duration.flatMap { $0 > 0 ? $0 : nil },
            positionSeconds: Self.number(items[4]).flatMap { $0 >= 0 ? $0 : nil }, trackID: Self.text(items[6]).flatMap { $0.isEmpty ? nil : $0 },
            artworkURL: items.count > 7 ? Self.text(items[7]).flatMap(URL.init(string:)) : nil
        )
    }

    private func artwork(for snapshot: AppPlayerSnapshot) async -> Data? {
        let key = snapshot.trackID ?? "\(snapshot.title)\u{1}\(snapshot.artist ?? "")\u{1}\(snapshot.album ?? "")"
        if let cover, cover.key == key { return cover.data }
        var data: Data?
        if let source = PlayerScripts.artwork(player) {
            if case .value(.data(let bytes)) = await runner.run(source), !bytes.isEmpty { data = bytes }
        } else if let url = snapshot.artworkURL {
            data = await fetchArtwork(url)
        }
        cover = (key, data)
        return data
    }

    private static func text(_ value: PlayerScriptValue) -> String? {
        switch value {
        case .text(let text): text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .number(let number): number.rounded() == number ? String(Int64(number)) : String(number)
        default: nil
        }
    }

    /// A number the script gave, or the text of one: with a point or, in a region that writes it so, a comma.
    private static func number(_ value: PlayerScriptValue) -> Double? {
        switch value {
        case .number(let number): number.isFinite ? number : nil
        case .text(let text): Double(text.replacingOccurrences(of: ",", with: ".")).flatMap { $0.isFinite ? $0 : nil }
        default: nil
        }
    }
}

/// The covers MyNotch fetches itself are Spotify's, from its own image service and nothing else, over https.
nonisolated enum SpotifyArtwork {
    static let maxBytes = 2_000_000

    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host()?.lowercased() else { return false }
        return host == "scdn.co" || host.hasSuffix(".scdn.co")
    }
}
