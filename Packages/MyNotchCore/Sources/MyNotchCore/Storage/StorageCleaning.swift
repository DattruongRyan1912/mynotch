import Foundation

/// One line of the Storage page: a kind of data a module keeps and how much room it takes.
nonisolated public struct StorageCategory: Identifiable, Equatable, Sendable {
    /// Stable and unique across modules, starting with the module id: "clipboard.images". `<module>.cache` is the generic
    /// category of every module (`StorageCenter.cacheCategoryID(for:)`) and is never reported by a module itself.
    public let id: String
    /// Vietnamese, sentence case.
    public let title: String
    public let bytes: Int64
    /// What cleaning never removes, e.g. "Giữ mục đã ghim, bảng và mục đã khoá"; nil when there is nothing to say.
    public let keeps: String?
    /// False for a category the page only shows, such as data the user must delete from the module itself.
    public let canClean: Bool

    public init(id: String, title: String, bytes: Int64, keeps: String? = nil, canClean: Bool = true) {
        self.id = id
        self.title = title
        self.bytes = bytes
        self.keeps = keeps
        self.canClean = canClean
    }
}

/// Adopted by a `FeatureModule` that keeps data of its own, beyond what `ModuleStorage.cachesDirectory` holds.
///
/// Every method works whether or not the module runs, from its `ModuleStorage` and files alone: nothing here may use state
/// that `start` creates. Report only what lives in `ModuleStorage.directory` or elsewhere; the content of `cachesDirectory`
/// is the generic cache category's, and counting it twice would inflate the total.
@MainActor public protocol StorageCleaning: AnyObject {
    /// The module's own categories. Measure off the main thread (`StorageFolder.bytes(in:)` does).
    func storageCategories(storage: ModuleStorage) async -> [StorageCategory]
    /// Removes what the category may lose and returns the bytes freed; never what its `keeps` note promises.
    func clean(categoryID: String, storage: ModuleStorage) async -> Int64
    /// Applies the module's own rules (retention, how many to keep) and returns the bytes freed. Called about every 24 hours; it
    /// must do nothing while the module is recording or exporting, which only the module knows.
    func autoClean(now: Date, storage: ModuleStorage) async -> Int64
    /// One line for the page, e.g. "Tự xoá sau 1 tháng, tối đa 500 mục"; nil when the module has no rule of its own.
    var autoCleanSummary: String? { get }
}

extension StorageCleaning {
    public func autoClean(now: Date, storage: ModuleStorage) async -> Int64 { 0 }
    public var autoCleanSummary: String? { nil }
}
