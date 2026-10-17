import Dispatch
import Testing
import LocalSocketKit

@Suite struct ServerGenerationTests {
    @Test func aNewCounterStartsAtZeroAndEachAdvanceMovesItOnByOne() {
        let generation = ServerGeneration()
        #expect(generation.current == 0)
        generation.advance()
        #expect(generation.current == 1)
        generation.advance()
        #expect(generation.current == 2)
    }

    /// What a server does: a closure takes the number when it is made, and work that finds another one when it runs is dropped.
    @Test func workQueuedBeforeAnAdvanceFindsAnotherNumberAndIsDropped() {
        let generation = ServerGeneration()
        let ticket = generation.current
        #expect(generation.current == ticket)
        generation.advance()
        #expect(generation.current != ticket)
    }

    @Test func advancesFromSeveralThreadsAreNotLost() {
        let generation = ServerGeneration()
        DispatchQueue.concurrentPerform(iterations: 400) { _ in generation.advance() }
        #expect(generation.current == 400)
    }
}
