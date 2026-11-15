import Foundation
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite("StorageScope Tests")
struct StorageScopeTests {
    private func makeFixture(modules: [any FeatureModule]) -> (center: StorageCenter, fake: StorageFakeModule?) {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let scheduler = ManualScheduler()
        let base = ScratchFolders.shared.reserve("scope-test")
        let root = StorageRoot(
            applicationSupport: base.appending(path: "Support"),
            caches: base.appending(path: "Caches")
        )
        let fake = modules.first as? StorageFakeModule
        let center = StorageCenter(
            modules: modules,
            settings: settings,
            scheduler: scheduler,
            storageRoot: root
        )
        return (center, fake)
    }

    @Test
    func storageGroupBytesOnlyCountsModuleScope() {
        let catModule = StorageCategory(id: "mod.1", title: "Module Data", bytes: 100, scope: .module)
        let catDev = StorageCategory(id: "dev.1", title: "DerivedData", bytes: 500, scope: .developer)
        let catSys = StorageCategory(id: "sys.1", title: "User Caches", bytes: 1000, scope: .system)

        let group = StorageGroup(
            id: ModuleID("test"),
            name: "Test",
            systemImage: "folder",
            categories: [catModule, catDev, catSys],
            autoCleanSummary: nil
        )

        // Only .module scope should be counted in group bytes
        #expect(group.bytes == 100)
    }

    @Test
    func cleanableBytesAndCleanAllLeaveOutDeveloperAndSystemScopes() async {
        let catMod = StorageCategory(id: "mod.cleanable", title: "Mod", bytes: 150, canClean: true, scope: .module)
        let catDev = StorageCategory(id: "dev.cache", title: "Dev", bytes: 500, canClean: true, scope: .developer)
        let catSys = StorageCategory(id: "sys.trash", title: "Sys", bytes: 2000, canClean: true, scope: .system)

        let fake = StorageFakeModule(ModuleID("cleaner"), categories: [catMod, catDev, catSys])
        let (center, _) = makeFixture(modules: [fake])

        await center.refresh()

        // cleanableBytes must ONLY sum .module scope cleanables (150 bytes)
        #expect(center.cleanableBytes == 150)

        // cleanAll must only clean .module category
        let freed = await center.cleanAll()
        #expect(freed == 150)
        #expect(fake.cleaned == ["mod.cleanable"])
    }

    @Test
    func categoriesInScopeFiltersCorrectly() async {
        let catMod = StorageCategory(id: "mod.1", title: "Mod", bytes: 10, scope: .module)
        let catDev1 = StorageCategory(id: "dev.1", title: "Dev 1", bytes: 20, scope: .developer)
        let catDev2 = StorageCategory(id: "dev.2", title: "Dev 2", bytes: 30, scope: .developer)
        let catSys = StorageCategory(id: "sys.1", title: "Sys", bytes: 40, scope: .system)

        let fake = StorageFakeModule(ModuleID("mock"), categories: [catMod, catDev1, catDev2, catSys])
        let (center, _) = makeFixture(modules: [fake])

        await center.refresh()

        let devCats = center.categories(in: .developer)
        #expect(devCats.count == 2)
        #expect(devCats.map(\.id) == ["dev.1", "dev.2"])

        let sysCats = center.categories(in: .system)
        #expect(sysCats.count == 1)
        #expect(sysCats.first?.id == "sys.1")
    }

    @Test
    func needsFullDiskAccessPropagated() async {
        let normalCat = StorageCategory(id: "cat.1", title: "Normal", bytes: 50, needsFullDiskAccess: false)
        let fake1 = StorageFakeModule(ModuleID("mod1"), categories: [normalCat])
        let (center1, _) = makeFixture(modules: [fake1])
        await center1.refresh()
        #expect(center1.needsFullDiskAccess == false)

        let fdaCat = StorageCategory(id: "cat.2", title: "FDA", bytes: 0, needsFullDiskAccess: true)
        let fake2 = StorageFakeModule(ModuleID("mod2"), categories: [normalCat, fdaCat])
        let (center2, _) = makeFixture(modules: [fake2])
        await center2.refresh()
        #expect(center2.needsFullDiskAccess == true)
    }
}
