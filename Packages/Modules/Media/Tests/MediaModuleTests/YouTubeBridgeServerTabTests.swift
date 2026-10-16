import Foundation
import Testing
@testable import MediaModule
@testable import YouTubeBridgeKit

/// The connection a message came in on, the end of a connection, and the commands the app writes to one tab's host.
@Suite final class YouTubeBridgeServerTabTests {
    let directory = URL(filePath: "/tmp/mn-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
    var path: String { directory.appending(path: "youtube.sock").path }
    var received: [(message: YouTubeMessage, connection: Int)] = []
    var ended: [Int] = []
    /// What the callbacks saw, in the order they ran.
    var order: [String] = []

    deinit { try? FileManager.default.removeItem(at: directory) }

    func makeServer() -> YouTubeBridgeServer {
        YouTubeBridgeServer(
            socketPath: path,
            onMessage: { [unowned self] message, connection in
                received.append((message, connection))
                order.append("message \(connection)")
            },
            onDisconnect: { [unowned self] connection in
                ended.append(connection)
                order.append("disconnect \(connection)")
            }
        )
    }

    @Test func eachMessageIsHandedOnWithTheConnectionItCameIn() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let first = try #require(YouTubeTestClient(path: path))
        let second = try #require(YouTubeTestClient(path: path))
        // One at a time: two connections are read on their own and a pair of writes may arrive in either order.
        first.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.tab(1)))
        await waitUntil { received.count == 1 }
        second.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.tab(1, title: "Other")))
        await waitUntil { received.count == 2 }
        first.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.tab(2)))
        await waitUntil { received.count == 3 }
        #expect(received.map(\.message) == [YouTubeTestMessages.tab(1), YouTubeTestMessages.tab(1, title: "Other"), YouTubeTestMessages.tab(2)])
        #expect(received[0].connection == received[2].connection, "one connection, one number")
        #expect(received[0].connection != received[1].connection, "and two Chromes with the same tab id are told apart")
    }

    @Test func aMessageMadeToFitTheOldCallbackStillComesWithoutConnections() async throws {
        var plain: [YouTubeMessage] = []
        let server = YouTubeBridgeServer(socketPath: path) { plain.append($0) }
        try server.start()
        defer { server.stop() }
        let client = try #require(YouTubeTestClient(path: path))
        client.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.tab(1)))
        await waitUntil { plain.count == 1 }
        #expect(plain == [YouTubeTestMessages.tab(1)])
    }

    @Test func theEndOfAConnectionIsToldOnceAfterWhatItSent() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        do {
            let client = try #require(YouTubeTestClient(path: path))
            client.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.tab(1)))
            client.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.tab(2)))
            await waitUntil { received.count == 2 }
        }
        await waitUntil { !ended.isEmpty }
        let connection = received[0].connection
        #expect(ended == [connection])
        #expect(order == ["message \(connection)", "message \(connection)", "disconnect \(connection)"])
        let other = try #require(YouTubeTestClient(path: path))
        other.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.tab(1)))
        await waitUntil { received.count == 3 }
        #expect(ended.count == 1, "another connection ending later is another notice, not this one again")
        // A connection that reuses the number comes after the notice, so what it sends is not taken for the old one's.
        #expect(order.last == "message \(received[2].connection)")
    }

    @Test func aConnectionThatBrokeTheFramingIsToldEndedToo() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let bad = try #require(YouTubeTestClient(path: path))
        bad.send(Data([0x00, 0x40, 0x00, 0x01]) + Data("x".utf8))
        await waitUntil { !ended.isEmpty }
        #expect(ended.count == 1)
    }

    @Test func stoppingTheServerTellsNothing() async throws {
        let server = makeServer()
        try server.start()
        let client = try #require(YouTubeTestClient(path: path))
        client.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.tab(1)))
        await waitUntil { received.count == 1 }
        server.stop()
        try await Task.sleep(for: .milliseconds(100))
        #expect(ended.isEmpty, "the module forgets everything itself when it stops the server")
    }

    // MARK: commands for a tab

    @Test func aTabCommandGoesAsExactlyItsFrameToTheConnectionNamedAndNoOther() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let first = try #require(YouTubeTestClient(path: path))
        let second = try #require(YouTubeTestClient(path: path))
        first.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.tab(1)))
        await waitUntil { received.count == 1 }
        second.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.tab(1)))
        await waitUntil { received.count == 2 }
        let command = TabCommand(tab: 1, action: .seek(seconds: 42.5))
        #expect(server.send(command, toConnection: received[1].connection))
        #expect(second.receiveFrames(count: 1) == [command.json])
        #expect(!first.hasUnreadData, "only the Chrome that owns the tab is asked")

        #expect(server.send(TabCommand(tab: 1, action: .pause), toConnection: received[0].connection))
        #expect(first.receiveFrames(count: 1) == [TabCommand(tab: 1, action: .pause).json])
        #expect(!second.hasUnreadData)
    }

    @Test func aTabCommandNeedsNoPlaybackAndDoesNotMoveTheHostThatSkipsGoTo() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let youtube = try #require(YouTubeTestClient(path: path))
        let tabs = try #require(YouTubeTestClient(path: path))
        youtube.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.playback()))
        await waitUntil { received.count == 1 }
        tabs.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.tab(1)))
        await waitUntil { received.count == 2 }
        #expect(server.send(TabCommand(tab: 1, action: .play), toConnection: received[1].connection))
        _ = tabs.receiveFrames(count: 1)
        #expect(server.send(.next), "next and previous for YouTube still go to the host whose page sent playback")
        #expect(youtube.receiveFrames(count: 1) == [YouTubeCommand.next.json])
        #expect(!tabs.hasUnreadData)
    }

    @Test func aConnectionThatIsNotThereIsNotWrittenTo() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        #expect(!server.send(TabCommand(tab: 1, action: .play), toConnection: 99), "no such connection")
        #expect(!server.send(TabCommand(tab: 1, action: .play), toConnection: Int.max), "not even a descriptor")
        #expect(!server.send(TabCommand(tab: 1, action: .play), toConnection: -1))
        let client = try #require(YouTubeTestClient(path: path))
        client.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.tab(1)))
        await waitUntil { received.count == 1 }
        let connection = received[0].connection
        #expect(server.send(TabCommand(tab: 1, action: .play), toConnection: connection))
        _ = client.receiveFrames(count: 1)
        server.stop()
        #expect(!server.send(TabCommand(tab: 1, action: .play), toConnection: connection), "a stopped server sends nothing")
    }

    @Test func aClientThatClosedIsNotWrittenToAfterItsEndWasTold() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        var connection = 0
        do {
            let client = try #require(YouTubeTestClient(path: path))
            client.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.tab(1)))
            await waitUntil { received.count == 1 }
            connection = received[0].connection
        }
        await waitUntil { !ended.isEmpty }
        #expect(!server.send(TabCommand(tab: 1, action: .play), toConnection: connection))
    }

    @Test func aNumberIsNeverGivenToTwoConnectionsSoAPressOnAGoneChromeCannotReachTheNext() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        var old = 0
        do {
            let client = try #require(YouTubeTestClient(path: path))
            client.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.tab(1)))
            await waitUntil { received.count == 1 }
            old = received[0].connection
        }
        await waitUntil { !ended.isEmpty }
        // The descriptor the first connection had is free now and is the one the next connection most likely gets.
        let next = try #require(YouTubeTestClient(path: path))
        next.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.tab(1)))
        await waitUntil { received.count == 2 }
        #expect(received[1].connection != old)
        #expect(!server.send(TabCommand(tab: 1, action: .pause), toConnection: old), "the Chrome that was there is gone")
        #expect(!next.hasUnreadData, "and what was meant for it is not written to the one that took its descriptor")
        #expect(server.send(TabCommand(tab: 1, action: .pause), toConnection: received[1].connection))
        #expect(next.receiveFrames(count: 1) == [TabCommand(tab: 1, action: .pause).json])
    }
}
