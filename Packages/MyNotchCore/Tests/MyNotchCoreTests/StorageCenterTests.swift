import Foundation
import SwiftUI
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

/// A module with data of its own: it reports and cleans categories from its `ModuleStorage` alone, so it works whether or
/// not it runs.
final class StorageFakeModule: FeatureModule, StorageCleaning {
    let descriptor: ModuleDescriptor
    var categories: [StorageCategory]
    var autoCleanFreed: Int64 = 0
    private(set) var cleaned: [String] = []
    private(set) var autoCleanDates: [Date] = []
    private(set) var storagesSeen: [ModuleStorage] = []
    var autoCleanSummary: String?

    init(_ id: ModuleID, defaultEnabled: Bool = true, categories: [StorageCategory] = []) {
        descriptor = ModuleDescriptor(id: id, displayName: id.rawValue, systemImage: "circle", defaultEnabled: defaultEnabled, order: 0)
        self.categories = categories
    }

    func storageCategories(storage: ModuleStorage) async -> [StorageCategory] {
        storagesSeen.append(storage)
        return categories
    }

    func clean(categoryID: String, storage: ModuleStorage) async -> Int64 {
        cleaned.append(categoryID)
        return categories.first { $0.id == categoryID }?.bytes ?? 0
    }

    func autoClean(now: Date, storage: ModuleStorage) async -> Int64 {
        autoCleanDates.append(now)
        return autoCleanFreed
    }

    func start(_ context: ModuleContext) async throws(ModuleError) {}
    func stop() async {}
    func makeTab() -> NotchTab? { nil }
    func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? { nil }
}

@Suite struct StorageCenterTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    /// The lines the center reported, in order.
    private final class ReportedLines {
        var lines: [String] = []
    }

    /// A center on temporary folders, a manual scheduler, a fixed clock and a log it can read back.
    private final class Fixture {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let scheduler = ManualScheduler()
        let root: StorageRoot = {
            let base = ScratchFolders.shared.reserve("center")
            return StorageRoot(applicationSupport: base.appending(path: "Support"), caches: base.appending(path: "Caches"))
        }()
        private let log = ReportedLines()
        let center: StorageCenter

        init(_ modules: [any FeatureModule], now: Date) {
            let log = log
            center = StorageCenter(
                modules: modules, settings: settings, scheduler: scheduler, storageRoot: root, now: { now }, report: { log.lines.append($0) }
            )
        }

        var messages: [String] { log.lines }

        func storage(_ id: ModuleID) -> ModuleStorage { root.storage(for: id) }
    }

    private func fixture(_ modules: [any FeatureModule]) -> Fixture { Fixture(modules, now: now) }

    private func category(_ group: StorageGroup, _ id: String) -> StorageCategory? { group.categories.first { $0.id == id } }

    // MARK: Categories

    @Test func aModuleThatDoesNotAdoptTheProtocolGetsOnlyTheCacheCategory() async throws {
        let plain = FakeModule("plain")
        let f = fixture([plain])
        try writeFile(f.storage("plain").cachesDirectory.appending(path: "a.bin"), bytes: 123)

        await f.center.refresh()

        let group = try #require(f.center.groups.first)
        #expect(f.center.groups.count == 1)
        #expect(group.id == "plain")
        #expect(group.categories == [StorageCategory(id: "plain.cache", title: "Bộ nhớ tạm", bytes: 123, keeps: nil, canClean: true)])
        #expect(group.autoCleanSummary == nil)
    }

    @Test func aModuleWithItsOwnCategoriesGetsThemBeforeTheCacheCategory() async throws {
        let own = StorageCategory(id: "alpha.items", title: "Mục", bytes: 5_000, keeps: "Giữ mục đã ghim", canClean: true)
        let module = StorageFakeModule("alpha", categories: [own])
        module.autoCleanSummary = "Tự xoá sau 1 tháng"
        let f = fixture([module])
        try writeFile(f.storage("alpha").cachesDirectory.appending(path: "a.bin"), bytes: 200)

        await f.center.refresh()

        let group = try #require(f.center.groups.first)
        #expect(group.categories.map(\.id) == ["alpha.items", "alpha.cache"])
        #expect(group.categories.first == own)
        #expect(group.bytes == 5_200)
        #expect(group.name == "alpha")
        #expect(group.systemImage == "circle")
        #expect(group.autoCleanSummary == "Tự xoá sau 1 tháng")
        #expect(f.center.total == 5_200)
        #expect(module.storagesSeen.map(\.cachesDirectory) == [f.storage("alpha").cachesDirectory])
    }

    @Test func aModuleCannotTakeOverTheCacheCategoryId() async throws {
        let rogue = StorageCategory(id: "alpha.cache", title: "Của module", bytes: 999_999, keeps: nil, canClean: false)
        let f = fixture([StorageFakeModule("alpha", categories: [rogue])])
        await f.center.refresh()
        let group = try #require(f.center.groups.first)
        #expect(group.categories.map(\.title) == ["Bộ nhớ tạm"])
        #expect(group.bytes == 0)
    }

    @Test func totalAddsEveryModule() async throws {
        let f = fixture([FakeModule("a"), FakeModule("b")])
        try writeFile(f.storage("a").cachesDirectory.appending(path: "x"), bytes: 100)
        try writeFile(f.storage("b").cachesDirectory.appending(path: "y"), bytes: 20)
        await f.center.refresh()
        #expect(f.center.groups.map(\.id) == ["a", "b"])
        #expect(f.center.total == 120)
        #expect(f.center.isMeasuring == false)
    }

    @Test func modulesThatAreOffAreStillMeasured() async throws {
        let off = StorageFakeModule(
            "off", defaultEnabled: false,
            categories: [StorageCategory(id: "off.items", title: "Mục", bytes: 700, keeps: nil, canClean: true)]
        )
        let plainOff = FakeModule("plainoff", defaultEnabled: false)
        let harness = RegistryHarness([off, plainOff])
        try writeFile(harness.storageRoot.storage(for: "plainoff").cachesDirectory.appending(path: "a.bin"), bytes: 33)
        let center = harness.registry.storageCenter

        await center.refresh()

        #expect(harness.registry.state(of: "off") == .disabled)
        #expect(harness.registry.state(of: "plainoff") == .disabled)
        #expect(center.groups.first { $0.id == "off" }?.bytes == 700)
        #expect(center.groups.first { $0.id == "plainoff" }?.bytes == 33)
        let freed = await center.clean("off.items")
        #expect(freed == 700)
        #expect(off.cleaned == ["off.items"])
        #expect(await center.clean("plainoff.cache") == 33)
    }

    @Test func theRegistryHandsOutACenterWithoutSchedulingAnything() async throws {
        let harness = RegistryHarness([FakeModule("a")])
        await harness.registry.bootstrap()
        _ = harness.registry.storageCenter
        #expect(harness.scheduler.pendingCount == 0)
    }

    // MARK: Cleaning

    @Test func cleaningTheCacheCategoryEmptiesOnlyThatModulesCachesFolder() async throws {
        let f = fixture([FakeModule("a"), FakeModule("b")])
        let aCache = try writeFile(f.storage("a").cachesDirectory.appending(path: "sub/x"), bytes: 100)
        let aDurable = try writeFile(f.storage("a").directory.appending(path: "keep.json"), bytes: 50)
        let bCache = try writeFile(f.storage("b").cachesDirectory.appending(path: "y"), bytes: 20)
        await f.center.refresh()

        let freed = await f.center.clean("a.cache")

        #expect(freed == 100)
        #expect(!storageItemExists(aCache))
        #expect(storageItemExists(f.storage("a").cachesDirectory))
        #expect(storageItemExists(aDurable))
        #expect(storageItemExists(bCache))
        #expect(f.center.total == 20)
    }

    @Test func cleaningACategoryCallsTheModuleWithItsId() async throws {
        let items = StorageCategory(id: "alpha.items", title: "Mục", bytes: 5_000, keeps: nil, canClean: true)
        let module = StorageFakeModule("alpha", categories: [items])
        let f = fixture([module])
        await f.center.refresh()
        #expect(await f.center.clean("alpha.items") == 5_000)
        #expect(module.cleaned == ["alpha.items"])
    }

    @Test func aCategoryThatCannotBeCleanedOrIsUnknownFreesNothingAndCallsNoOne() async throws {
        let locked = StorageCategory(id: "alpha.locked", title: "Khoá", bytes: 800, keeps: nil, canClean: false)
        let module = StorageFakeModule("alpha", categories: [locked])
        let f = fixture([module])
        await f.center.refresh()
        #expect(await f.center.clean("alpha.locked") == 0)
        #expect(await f.center.clean("nobody.items") == 0)
        #expect(module.cleaned.isEmpty)
        #expect(f.center.total == 800)
    }

    @Test func cleanAllCallsEveryCleanableCategoryAndNoOther() async throws {
        let a = StorageFakeModule("alpha", categories: [
            StorageCategory(id: "alpha.one", title: "Một", bytes: 100, keeps: nil, canClean: true),
            StorageCategory(id: "alpha.locked", title: "Khoá", bytes: 900, keeps: nil, canClean: false),
            StorageCategory(id: "alpha.empty", title: "Trống", bytes: 0, keeps: nil, canClean: true),
        ])
        let b = StorageFakeModule("beta", categories: [StorageCategory(id: "beta.two", title: "Hai", bytes: 30, keeps: nil, canClean: true)])
        let plain = FakeModule("plain")
        let f = fixture([a, b, plain])
        let cache = try writeFile(f.storage("plain").cachesDirectory.appending(path: "x"), bytes: 7)

        let freed = await f.center.cleanAll()

        #expect(a.cleaned == ["alpha.one", "alpha.empty"])
        #expect(b.cleaned == ["beta.two"])
        #expect(!storageItemExists(cache))
        #expect(freed == 137)
        #expect(f.center.isCleaning == false)
    }

    @Test func cleanableBytesLeaveOutWhatCannotBeCleaned() async throws {
        let a = StorageFakeModule("alpha", categories: [
            StorageCategory(id: "alpha.one", title: "Một", bytes: 100, keeps: nil, canClean: true),
            StorageCategory(id: "alpha.locked", title: "Khoá", bytes: 900, keeps: nil, canClean: false),
        ])
        let f = fixture([a])
        await f.center.refresh()
        #expect(f.center.total == 1_000)
        #expect(f.center.cleanableBytes == 100)
    }

    // MARK: Automatic rules

    @Test func theAgeRuleRemovesOldCacheFilesAndKeepsFreshOnesAndDurableData() async throws {
        let f = fixture([FakeModule("a")])
        let cache = f.storage("a").cachesDirectory
        let old = try writeFile(cache.appending(path: "sub/old.bin"), bytes: 100, modified: now.addingTimeInterval(-31 * day))
        let fresh = try writeFile(cache.appending(path: "fresh.bin"), bytes: 100, modified: now.addingTimeInterval(-29 * day))
        let durableOld = try writeFile(f.storage("a").directory.appending(path: "history.json"), bytes: 100, modified: now.addingTimeInterval(-400 * day))

        let freed = await f.center.autoClean(now: now)

        #expect(freed == 100)
        #expect(!storageItemExists(old))
        #expect(storageItemExists(fresh))
        #expect(storageItemExists(durableOld))
    }

    @Test func theAgeLimitIsASettingInDays() async throws {
        let f = fixture([FakeModule("a")])
        let file = try writeFile(f.storage("a").cachesDirectory.appending(path: "x"), bytes: 10, modified: now.addingTimeInterval(-8 * day))
        #expect(await f.center.autoClean(now: now) == 0)
        #expect(storageItemExists(file))

        f.settings.set(7, for: StorageCenter.cacheMaxAgeDaysKey)
        #expect(await f.center.autoClean(now: now) == 10)
        #expect(!storageItemExists(file))
    }

    @Test func theSizeRuleCoversEveryModulesCachesTogetherAndTakesTheOldestFirst() async throws {
        let f = fixture([FakeModule("a"), FakeModule("b")])
        f.settings.set(50, for: StorageCenter.cacheMaxMBKey)
        let a1 = try writeSparseFile(f.storage("a").cachesDirectory.appending(path: "a1"), bytes: 30_000_000, modified: now.addingTimeInterval(-3 * day))
        let b1 = try writeSparseFile(f.storage("b").cachesDirectory.appending(path: "b1"), bytes: 30_000_000, modified: now.addingTimeInterval(-2 * day))
        let a2 = try writeSparseFile(f.storage("a").cachesDirectory.appending(path: "sub/a2"), bytes: 30_000_000, modified: now.addingTimeInterval(-1 * day))
        let durable = try writeSparseFile(f.storage("a").directory.appending(path: "big"), bytes: 500_000_000, modified: now.addingTimeInterval(-300 * day))

        let freed = await f.center.autoClean(now: now)

        #expect(freed == 60_000_000)
        #expect(!storageItemExists(a1))
        #expect(!storageItemExists(b1))
        #expect(storageItemExists(a2))
        #expect(storageItemExists(durable))
    }

    @Test func theSettingsHaveTheirDefaultsAndStayInRange() {
        let f = fixture([])
        #expect(StorageCenter.cacheMaxAgeDaysKey.name == "app.storage.cacheMaxAgeDays")
        #expect(StorageCenter.cacheMaxMBKey.name == "app.storage.cacheMaxMB")
        #expect(f.settings.value(StorageCenter.cacheMaxAgeDaysKey) == 30)
        #expect(f.settings.value(StorageCenter.cacheMaxMBKey) == 200)
        f.settings.set(0, for: StorageCenter.cacheMaxAgeDaysKey)
        f.settings.set(0, for: StorageCenter.cacheMaxMBKey)
        #expect(f.settings.value(StorageCenter.cacheMaxAgeDaysKey) == 1)
        #expect(f.settings.value(StorageCenter.cacheMaxMBKey) == 50)
    }

    @Test func autoCleanAsksEveryModuleToApplyItsOwnRulesEvenWhenItIsOff() async throws {
        let off = StorageFakeModule("off", defaultEnabled: false)
        off.autoCleanFreed = 40
        let plain = FakeModule("plain")
        let f = fixture([off, plain])
        let freed = await f.center.autoClean(now: now)
        #expect(off.autoCleanDates == [now])
        #expect(freed == 40)
    }

    // MARK: Schedule

    @Test func theAutoRunStartsThirtySecondsAfterLaunchThenEveryTwentyFourHours() async throws {
        let module = StorageFakeModule("alpha")
        let f = fixture([module])

        f.center.startAutoClean()
        f.center.startAutoClean()
        #expect(f.scheduler.pendingCount == 1)

        f.scheduler.advance(by: .seconds(29))
        #expect(module.autoCleanDates.isEmpty)
        f.scheduler.advance(by: .seconds(1))
        await f.center.autoCleanTask?.value
        #expect(module.autoCleanDates == [now])
        #expect(f.scheduler.pendingCount == 1)

        f.scheduler.advance(by: .seconds(24 * 3_600 - 1))
        #expect(module.autoCleanDates.count == 1)
        f.scheduler.advance(by: .seconds(1))
        await f.center.autoCleanTask?.value
        #expect(module.autoCleanDates.count == 2)

        f.scheduler.advance(by: .seconds(24 * 3_600))
        await f.center.autoCleanTask?.value
        #expect(module.autoCleanDates.count == 3)
        #expect(f.scheduler.pendingCount == 1)
    }

    @Test func stoppingTheAutoRunCancelsIt() async throws {
        let module = StorageFakeModule("alpha")
        let f = fixture([module])
        f.center.startAutoClean()
        f.center.stopAutoClean()
        #expect(f.scheduler.pendingCount == 0)
        f.scheduler.advance(by: .seconds(100_000))
        #expect(module.autoCleanDates.isEmpty)

        f.center.startAutoClean()
        #expect(f.scheduler.pendingCount == 1)
    }

    // MARK: Log

    @Test func theLogHoldsNumbersOnlyNeverPathsOrContent() async throws {
        let secretName = "secret-file-name.bin"
        let f = fixture([FakeModule("plain"), StorageFakeModule("alpha", categories: [
            StorageCategory(id: "alpha.items", title: "Mục bí mật", bytes: 10, keeps: "Giữ ghi chú bí mật", canClean: true),
        ])])
        let cache = f.storage("plain").cachesDirectory
        try writeFile(cache.appending(path: secretName), bytes: 10)
        try writeFile(cache.appending(path: "old-\(secretName)"), bytes: 10, modified: now.addingTimeInterval(-90 * day))
        await f.center.refresh()

        await f.center.clean("plain.cache")
        await f.center.clean("alpha.items")
        await f.center.cleanAll()
        await f.center.autoClean(now: now)

        #expect(!f.messages.isEmpty)
        for message in f.messages {
            #expect(!message.contains("/"))
            #expect(!message.contains(secretName))
            #expect(!message.contains("secret"))
            #expect(!message.contains("aaaa"))
            #expect(!message.contains("bí mật"))
            #expect(!message.contains("alpha"))
            #expect(!message.contains("plain"))
        }
    }

    @Test func theLogSaysHowMuchWasFreed() async throws {
        let f = fixture([FakeModule("plain")])
        try writeFile(f.storage("plain").cachesDirectory.appending(path: "x"), bytes: 1_234)
        await f.center.refresh()
        await f.center.clean("plain.cache")
        #expect(f.messages.contains { $0.contains("1234") })
    }
}
