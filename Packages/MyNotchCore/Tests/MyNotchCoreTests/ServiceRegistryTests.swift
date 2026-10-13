import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct ServiceRegistryTests {
    let scheduler = ManualScheduler()
    let registry: ServiceRegistry

    init() {
        registry = ServiceRegistry(scheduler: scheduler)
    }

    @Test func handleForwardsTheTextToTheRegisteredHandler() {
        var received: [String] = []
        registry.register("translate", owner: "translation") { received.append($0) }
        #expect(registry.handle(name: "translate", text: "xin chào"))
        #expect(received == ["xin chào"])
        #expect(registry.handle(name: "unknown", text: "ignored"))
        #expect(received == ["xin chào"])
    }

    @Test func unregisterAllRemovesOnlyThatOwnersServices() {
        var received: [String] = []
        registry.register("translate", owner: "translation") { received.append("translate \($0)") }
        registry.register("define", owner: "dictionary") { received.append("define \($0)") }
        registry.unregisterAll(owner: "translation")
        #expect(registry.handle(name: "translate", text: "a"))
        #expect(registry.handle(name: "define", text: "b"))
        scheduler.advance(by: .seconds(10))
        #expect(received == ["define b"])
    }

    @Test func aReplacedServiceSurvivesItsPreviousOwnerStopping() {
        var handledBy: [String] = []
        registry.register("translate", owner: "old") { _ in handledBy.append("old") }
        registry.register("translate", owner: "new") { _ in handledBy.append("new") }
        registry.unregisterAll(owner: "old")
        #expect(registry.handle(name: "translate", text: "a"))
        #expect(handledBy == ["new"])
    }

    @Test func invalidatedModuleServicesUnregisterAndIgnoreLateRegistrations() {
        let services = ModuleServices(registry: registry, module: "translation")
        var received: [String] = []
        services.register("translate") { received.append($0) }
        #expect(registry.handle(name: "translate", text: "a"))
        services.invalidate()
        #expect(registry.handle(name: "translate", text: "b"))
        services.register("late") { received.append($0) }
        #expect(registry.handle(name: "late", text: "c"))
        scheduler.advance(by: .seconds(10))
        #expect(received == ["a"])
    }

    @Test func aRequestBeforeItsHandlerReachesTheFirstHandlerRegisteredWithinTenSeconds() {
        var received: [String] = []
        #expect(registry.handle(name: "translate", text: "early"))
        scheduler.advance(by: .seconds(9))
        registry.register("translate", owner: "translation") { received.append($0) }
        #expect(received.isEmpty)
        scheduler.advance(by: .zero)
        #expect(received == ["early"])

        registry.register("translate", owner: "translation") { received.append("again \($0)") }
        scheduler.advance(by: .seconds(10))
        #expect(received == ["early"])
        #expect(scheduler.pendingCount == 0)
    }

    @Test func aQueuedRequestExpiresAfterTenSeconds() {
        var received: [String] = []
        #expect(registry.handle(name: "translate", text: "early"))
        scheduler.advance(by: .seconds(10))
        registry.register("translate", owner: "translation") { received.append($0) }
        scheduler.advance(by: .zero)
        #expect(received.isEmpty)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func aNewerRequestReplacesTheQueuedOneAndRestartsTheWait() {
        var received: [String] = []
        #expect(registry.handle(name: "translate", text: "first"))
        scheduler.advance(by: .seconds(5))
        #expect(registry.handle(name: "translate", text: "second"))
        scheduler.advance(by: .seconds(6))
        registry.register("translate", owner: "translation") { received.append($0) }
        scheduler.advance(by: .zero)
        #expect(received == ["second"])
        #expect(scheduler.pendingCount == 0)
    }

    @Test func aLateExpiryOfAReplacedRequestKeepsTheNewerOne() {
        let scheduler = UncancellableScheduler()
        let registry = ServiceRegistry(scheduler: scheduler)
        var received: [String] = []
        #expect(registry.handle(name: "translate", text: "first"))
        scheduler.base.advance(by: .seconds(5))
        #expect(registry.handle(name: "translate", text: "second"))
        scheduler.base.advance(by: .seconds(6))
        registry.register("translate", owner: "translation") { received.append($0) }
        scheduler.base.advance(by: .zero)
        #expect(received == ["second"])
    }

    @Test func queuesEachServiceSeparately() {
        var received: [String] = []
        #expect(registry.handle(name: "translate", text: "a"))
        #expect(registry.handle(name: "define", text: "b"))
        registry.register("define", owner: "dictionary") { received.append("define \($0)") }
        registry.register("translate", owner: "translation") { received.append("translate \($0)") }
        scheduler.advance(by: .zero)
        #expect(received == ["define b", "translate a"])
    }

    @Test func aRequestHandledDirectlySupersedesTheQueuedOne() {
        var received: [String] = []
        #expect(registry.handle(name: "translate", text: "old"))
        registry.register("translate", owner: "translation") { received.append($0) }
        #expect(registry.handle(name: "translate", text: "new"))
        scheduler.advance(by: .seconds(10))
        #expect(received == ["new"])
    }

    @Test func afterStartupARequestNoHandlerClaimsIsRefusedNotQueued() {
        var received: [String] = []
        registry.finishStartup()
        #expect(!registry.handle(name: "translate", text: "late"))
        #expect(scheduler.pendingCount == 0)
        registry.register("translate", owner: "translation") { received.append($0) }
        scheduler.advance(by: .seconds(10))
        #expect(received.isEmpty)
    }

    @Test func afterStartupARequestStillReachesARegisteredHandlerAndAStoppedModuleRefuses() {
        var received: [String] = []
        registry.finishStartup()
        registry.register("translate", owner: "translation") { received.append($0) }
        #expect(registry.handle(name: "translate", text: "a"))
        #expect(received == ["a"])
        registry.unregisterAll(owner: "translation")
        #expect(!registry.handle(name: "translate", text: "b"))
        #expect(received == ["a"])
    }

    @Test func finishingStartupDropsARequestNoModuleClaimedButKeepsOneAlreadyBeingDelivered() {
        var received: [String] = []
        #expect(registry.handle(name: "translate", text: "unclaimed"))
        #expect(registry.handle(name: "define", text: "claimed"))
        registry.register("define", owner: "dictionary") { received.append("define \($0)") }
        registry.finishStartup()
        #expect(scheduler.pendingCount == 2)
        scheduler.advance(by: .zero)
        #expect(received == ["define claimed"])
        registry.register("translate", owner: "translation") { received.append("translate \($0)") }
        scheduler.advance(by: .seconds(10))
        #expect(received == ["define claimed"])
        #expect(scheduler.pendingCount == 0)
    }

    @Test func aQueuedRequestWaitsForTheNextHandlerWhenItsHandlerLeavesBeforeDelivery() {
        var received: [String] = []
        #expect(registry.handle(name: "translate", text: "early"))
        registry.register("translate", owner: "failed") { received.append("failed \($0)") }
        registry.unregisterAll(owner: "failed")
        scheduler.advance(by: .seconds(1))
        #expect(received.isEmpty)
        registry.register("translate", owner: "retried") { received.append("retried \($0)") }
        scheduler.advance(by: .zero)
        #expect(received == ["retried early"])
    }
}
