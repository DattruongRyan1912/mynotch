import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import CleanerModule

@Suite("CleanerModule Lifecycle & Integration Tests")
@MainActor
struct CleanerModuleTests {
    @Test("Descriptor và thuộc tính mặc định chuẩn xác")
    func testDescriptor() {
        let module = CleanerModule()
        #expect(module.descriptor.id == "cleaner")
        #expect(module.descriptor.displayName == "Gỡ ứng dụng")
        #expect(module.descriptor.order == 970)
        #expect(module.descriptor.systemImage == "trash")
    }

    @Test("makeTab cấu hình đúng DropTypes và chiều cao chuẩn")
    func testMakeTab() {
        let module = CleanerModule()
        let tab = module.makeTab()
        #expect(tab != nil)
        #expect(tab?.id == "cleaner")
        #expect(tab?.preferredHeight == 220)
        #expect(tab?.dropTypes == CleanerModule.dropTypes)
    }

    @Test("Lifecycle bootstrap qua RegistryHarness")
    func testLifecycle() async throws {
        let module = CleanerModule()
        let harness = RegistryHarness([module])

        await harness.registry.bootstrap()
        #expect(module.context != nil)

        await module.stop()
        #expect(module.context == nil)
    }

    @Test("StorageCleaning trả về categories và dọn dẹp")
    func testStorageCleaning() async throws {
        let module = CleanerModule()
        let harness = RegistryHarness([module])
        let storage = harness.storageRoot.storage(for: "cleaner")

        let categories = await module.storageCategories(storage: storage)
        #expect(!categories.isEmpty)

        // Dọn một category không tồn tại hoặc rỗng trả về 0 bytes an toàn
        let freed = await module.clean(categoryID: "cleaner.dev.nonexistent", storage: storage)
        #expect(freed == 0)
    }

    @Test("DashboardSnapshot không chứa icon sparkles cấm theo chuẩn Anti-AI-slop")
    func testDashboardSnapshotContainsNoForbiddenSparklesSymbol() {
        let module = CleanerModule()
        let snapshot = module.dashboardSnapshot()
        #expect(snapshot.systemImage != "sparkles")
        #expect(snapshot.metrics.allSatisfy { $0.systemImage != "sparkles" })
    }
}
