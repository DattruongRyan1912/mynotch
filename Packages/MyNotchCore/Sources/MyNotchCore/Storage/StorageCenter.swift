import Foundation
import Observation

/// One module's part of the Storage page.
nonisolated public struct StorageGroup: Identifiable, Equatable, Sendable {
    public let id: ModuleID
    public let name: String
    public let systemImage: String
    /// The module's own categories, then its cache.
    public let categories: [StorageCategory]
    /// The module's `autoCleanSummary` when it was measured.
    public let autoCleanSummary: String?

    public var bytes: Int64 { categories.reduce(0) { $0 + $1.bytes } }
}

/// Measures and cleans what every module keeps on disk, and runs the automatic rules. Works from `ModuleStorage` and files
/// alone, so a module that is off is measured and cleaned like one that runs.
@Observable
public final class StorageCenter {
    public static let cacheMaxAgeDaysRange = 1...365
    public static let cacheMaxMBRange = 50...10_000

    /// Cache files older than this many days are deleted by the automatic rule.
    public static let cacheMaxAgeDaysKey = SettingKey<Int>("app.storage.cacheMaxAgeDays", default: 30, clampedTo: cacheMaxAgeDaysRange)
    /// Above this many megabytes (1 MB = 1,000,000 bytes, the unit the page shows) of cache in all modules together, the oldest
    /// files go first.
    public static let cacheMaxMBKey = SettingKey<Int>("app.storage.cacheMaxMB", default: 200, clampedTo: cacheMaxMBRange)

    /// Late enough that it never slows the launch.
    static let firstAutoCleanDelay: Duration = .seconds(30)
    static let autoCleanInterval: Duration = .seconds(24 * 60 * 60)
    static let cacheCategoryTitle = "Bộ nhớ tạm"

    /// The generic category every module has, for its `ModuleStorage.cachesDirectory`.
    public static func cacheCategoryID(for module: ModuleID) -> String { "\(module.rawValue).cache" }

    /// As of the last `refresh`, in module order.
    public private(set) var groups: [StorageGroup] = []
    public private(set) var isMeasuring = false
    /// True while a clean, manual or automatic, runs; a second one waits for the next try instead of overlapping.
    public private(set) var isCleaning = false

    @ObservationIgnored private let modules: [any FeatureModule]
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private let storageRoot: StorageRoot
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let report: (String) -> Void
    @ObservationIgnored private var autoCleanSchedule: ScheduledAction?
    /// Only the newest run, so a test can wait for it.
    @ObservationIgnored private(set) var autoCleanTask: Task<Void, Never>?
    /// Newer refreshes win: a slow measurement that finishes late must not replace a newer answer.
    @ObservationIgnored private var refreshGeneration = 0

    /// `report` receives one line per clean, made of numbers only; by default it goes to the log.
    public init(
        modules: [any FeatureModule], settings: SettingsStore, scheduler: any Scheduler, storageRoot: StorageRoot,
        now: @escaping () -> Date = Date.init, report: ((String) -> Void)? = nil
    ) {
        self.modules = modules
        self.settings = settings
        self.scheduler = scheduler
        self.storageRoot = storageRoot
        self.now = now
        self.report = report ?? { Log.logger(category: "storage").info("\($0, privacy: .public)") }
    }

    public var total: Int64 { groups.reduce(0) { $0 + $1.bytes } }

    /// What "clean everything" frees: the categories that can be cleaned.
    public var cleanableBytes: Int64 {
        groups.flatMap(\.categories).filter(\.canClean).reduce(0) { $0 + $1.bytes }
    }

    /// Measures every module again. Shows the old numbers until the new ones are in.
    public func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        isMeasuring = true
        let measured = await measure()
        guard generation == refreshGeneration else { return }
        groups = measured
        isMeasuring = false
    }

    /// Cleans one category, as measured by the last `refresh`, and measures again. Returns the bytes freed; 0 for a category that
    /// is unknown or cannot be cleaned, and when another clean is still running.
    @discardableResult
    public func clean(_ categoryID: String) async -> Int64 {
        guard !isCleaning,
              let owner = groups.first(where: { $0.categories.contains { $0.id == categoryID && $0.canClean } }),
              let module = modules.first(where: { $0.descriptor.id == owner.id }) else { return 0 }
        isCleaning = true
        defer { isCleaning = false }
        let freed = await perform(categoryID, of: module)
        report("clean: freed \(freed) bytes in 1 categories")
        await refresh()
        return freed
    }

    /// Cleans every category that can be cleaned, as measured now. Returns the bytes freed.
    @discardableResult
    public func cleanAll() async -> Int64 {
        guard !isCleaning else { return 0 }
        isCleaning = true
        defer { isCleaning = false }
        var freed: Int64 = 0
        var cleaned = 0
        for group in await measure() {
            guard let module = modules.first(where: { $0.descriptor.id == group.id }) else { continue }
            for category in group.categories where category.canClean {
                freed += await perform(category.id, of: module)
                cleaned += 1
            }
        }
        report("clean all: freed \(freed) bytes in \(cleaned) categories")
        await refresh()
        return freed
    }

    /// Applies each module's own rules, then the cache rule: files older than `cacheMaxAgeDaysKey` go, and when the caches of all
    /// modules together are over `cacheMaxMBKey`, the oldest of the rest. Returns the bytes freed.
    @discardableResult
    public func autoClean(now: Date) async -> Int64 {
        guard !isCleaning else { return 0 }
        isCleaning = true
        defer { isCleaning = false }
        var freed: Int64 = 0
        for module in modules {
            guard let cleaner = module as? any StorageCleaning else { continue }
            let own = await cleaner.autoClean(now: now, storage: storageRoot.storage(for: module.descriptor.id))
            freed += max(own, 0)
        }
        freed += await cleanCaches(now: now)
        report("auto clean: freed \(freed) bytes")
        if freed > 0 { await refresh() }
        return freed
    }

    /// Runs `autoClean` 30 seconds from now and every 24 hours after that. Does nothing when already started.
    public func startAutoClean() {
        guard autoCleanSchedule == nil else { return }
        schedule(after: Self.firstAutoCleanDelay)
    }

    public func stopAutoClean() {
        autoCleanSchedule?.cancel()
        autoCleanSchedule = nil
    }

    private func schedule(after delay: Duration) {
        // The next run is scheduled before this one starts, so a long clean never pushes the schedule back.
        autoCleanSchedule = scheduler.schedule(after: delay) { [weak self] in
            guard let self else { return }
            schedule(after: Self.autoCleanInterval)
            autoCleanTask = Task { await self.autoClean(now: self.now()) }
        }
    }

    private func measure() async -> [StorageGroup] {
        var groups: [StorageGroup] = []
        for module in modules {
            let descriptor = module.descriptor
            let storage = storageRoot.storage(for: descriptor.id)
            let cleaner = module as? any StorageCleaning
            let cacheID = Self.cacheCategoryID(for: descriptor.id)
            var categories = await cleaner?.storageCategories(storage: storage) ?? []
            categories.removeAll { $0.id == cacheID }
            categories.append(StorageCategory(
                id: cacheID, title: Self.cacheCategoryTitle, bytes: await StorageFolder.bytes(in: storage.cachesDirectory)
            ))
            groups.append(StorageGroup(
                id: descriptor.id, name: descriptor.displayName, systemImage: descriptor.systemImage, categories: categories,
                autoCleanSummary: cleaner?.autoCleanSummary
            ))
        }
        return groups
    }

    private func perform(_ categoryID: String, of module: any FeatureModule) async -> Int64 {
        let id = module.descriptor.id
        let storage = storageRoot.storage(for: id)
        if categoryID == Self.cacheCategoryID(for: id) {
            return await StorageFolder.removeContents(of: storage.cachesDirectory)
        }
        guard let cleaner = module as? any StorageCleaning else { return 0 }
        return max(await cleaner.clean(categoryID: categoryID, storage: storage), 0)
    }

    private func cleanCaches(now: Date) async -> Int64 {
        var files: [StorageFile] = []
        for module in modules {
            files += await StorageFolder.files(in: storageRoot.storage(for: module.descriptor.id).cachesDirectory)
        }
        let doomed = CachePolicy.removals(
            from: files, now: now,
            maxAge: TimeInterval(settings.value(Self.cacheMaxAgeDaysKey)) * 86_400,
            maxBytes: Int64(settings.value(Self.cacheMaxMBKey)) * 1_000_000
        )
        return await StorageFolder.remove(doomed)
    }
}
