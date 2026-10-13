import Testing
@testable import MyNotchCore

@Suite struct ServiceRegistryTests {
    @Test func handleForwardsTheTextToTheRegisteredHandler() {
        let registry = ServiceRegistry()
        var received: [String] = []
        registry.register("translate", owner: "translation") { received.append($0) }
        #expect(registry.handle(name: "translate", text: "xin chào"))
        #expect(received == ["xin chào"])
        #expect(!registry.handle(name: "unknown", text: "ignored"))
        #expect(received == ["xin chào"])
    }

    @Test func unregisterAllRemovesOnlyThatOwnersServices() {
        let registry = ServiceRegistry()
        registry.register("translate", owner: "translation") { _ in }
        registry.register("define", owner: "dictionary") { _ in }
        registry.unregisterAll(owner: "translation")
        #expect(!registry.handle(name: "translate", text: "a"))
        #expect(registry.handle(name: "define", text: "b"))
    }

    @Test func aReplacedServiceSurvivesItsPreviousOwnerStopping() {
        let registry = ServiceRegistry()
        var handledBy: [String] = []
        registry.register("translate", owner: "old") { _ in handledBy.append("old") }
        registry.register("translate", owner: "new") { _ in handledBy.append("new") }
        registry.unregisterAll(owner: "old")
        #expect(registry.handle(name: "translate", text: "a"))
        #expect(handledBy == ["new"])
    }

    @Test func invalidatedModuleServicesUnregisterAndIgnoreLateRegistrations() {
        let registry = ServiceRegistry()
        let services = ModuleServices(registry: registry, module: "translation")
        services.register("translate") { _ in }
        #expect(registry.handle(name: "translate", text: "a"))
        services.invalidate()
        #expect(!registry.handle(name: "translate", text: "a"))
        services.register("late") { _ in }
        #expect(!registry.handle(name: "late", text: "a"))
    }
}
