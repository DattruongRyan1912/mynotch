import Foundation
import Synchronization
import Testing
@testable import FanHelperKit

@Suite struct IdleExitTests {
    final class Exits: Sendable {
        let count = Mutex(0)
        func record() { count.withLock { $0 += 1 } }
        var value: Int { count.withLock { $0 } }
    }

    func idle(after seconds: TimeInterval = 0.05) -> (IdleExit, Exits) {
        let exits = Exits()
        return (IdleExit(after: seconds, queue: DispatchQueue(label: "test")) { exits.record() }, exits)
    }

    func pause(_ seconds: TimeInterval = 0.25) async { try? await Task.sleep(for: .seconds(seconds)) }

    @Test func exitsWhenNobodyEverConnects() async {
        let (idle, exits) = idle()
        idle.start()
        await pause()
        #expect(exits.value == 1)
    }

    @Test func doesNotExitWhileAConnectionIsOpen() async {
        let (idle, exits) = idle()
        idle.start()
        idle.connectionOpened()
        await pause()
        #expect(exits.value == 0)
    }

    @Test func exitsAfterTheLastConnectionClosed() async {
        let (idle, exits) = idle()
        idle.start()
        idle.connectionOpened()
        idle.connectionOpened()
        idle.connectionClosed()
        await pause()
        #expect(exits.value == 0)
        idle.connectionClosed()
        await pause()
        #expect(exits.value == 1)
    }

    @Test func aConnectionThatArrivesBeforeTheTimeIsUpKeepsItAlive() async {
        let (idle, exits) = idle(after: 0.2)
        idle.start()
        idle.connectionOpened()
        idle.connectionClosed()
        try? await Task.sleep(for: .seconds(0.1))
        idle.connectionOpened()
        await pause(0.4)
        #expect(exits.value == 0)
    }

    @Test func exitsOnlyOnce() async {
        let (idle, exits) = idle()
        idle.start()
        await pause()
        idle.connectionOpened()
        idle.connectionClosed()
        await pause()
        #expect(exits.value == 1)
    }

    @Test func closingMoreThanWasOpenedDoesNotGoBelowZero() async {
        let (idle, exits) = idle(after: 0.3)
        idle.connectionClosed()
        idle.connectionOpened()
        await pause(0.4)
        #expect(exits.value == 0)
    }
}
