import Foundation
import MyNotchCore

/// Catalog defining supported developer and system cleaning locations.
nonisolated public struct CleanerCatalogEntry: Sendable {
    public let id: String
    public let title: String
    public let scope: StorageScope
    public let relativePaths: [String]
    public let caution: String?

    public init(id: String, title: String, scope: StorageScope, relativePaths: [String], caution: String? = nil) {
        self.id = id
        self.title = title
        self.scope = scope
        self.relativePaths = relativePaths
        self.caution = caution
    }
}

nonisolated public enum CleanerCatalog {
    public static let entries: [CleanerCatalogEntry] = [
        // Developer Caches
        CleanerCatalogEntry(
            id: "cleaner.dev.deriveddata",
            title: "Xcode DerivedData",
            scope: .developer,
            relativePaths: ["Library/Developer/Xcode/DerivedData"],
            caution: "Đóng Xcode trước khi dọn dẹp"
        ),
        CleanerCatalogEntry(
            id: "cleaner.dev.swiftpm",
            title: "Swift Package Manager Cache",
            scope: .developer,
            relativePaths: ["Library/Caches/org.swift.swiftpm"]
        ),
        CleanerCatalogEntry(
            id: "cleaner.dev.cocoapods",
            title: "CocoaPods Cache",
            scope: .developer,
            relativePaths: ["Library/Caches/CocoaPods"]
        ),
        CleanerCatalogEntry(
            id: "cleaner.dev.npm",
            title: "npm Cache",
            scope: .developer,
            relativePaths: [".npm/_cacache"]
        ),
        CleanerCatalogEntry(
            id: "cleaner.dev.pnpm",
            title: "pnpm Store",
            scope: .developer,
            relativePaths: ["Library/pnpm/store"]
        ),
        CleanerCatalogEntry(
            id: "cleaner.dev.yarn",
            title: "Yarn Berry Cache",
            scope: .developer,
            relativePaths: [".yarn/berry/cache"]
        ),
        CleanerCatalogEntry(
            id: "cleaner.dev.cargo",
            title: "Rust Cargo Registry",
            scope: .developer,
            relativePaths: [".cargo/registry/cache", ".cargo/registry/src"]
        ),
        CleanerCatalogEntry(
            id: "cleaner.dev.homebrew",
            title: "Homebrew Download Cache",
            scope: .developer,
            relativePaths: ["Library/Caches/Homebrew"]
        ),

        // System Junk
        CleanerCatalogEntry(
            id: "cleaner.system.usercaches",
            title: "Bộ nhớ tạm ứng dụng",
            scope: .system,
            relativePaths: ["Library/Caches"]
        ),
        CleanerCatalogEntry(
            id: "cleaner.system.logs",
            title: "Nhật ký hệ thống & ứng dụng",
            scope: .system,
            relativePaths: ["Library/Logs"]
        ),
        CleanerCatalogEntry(
            id: "cleaner.system.trash",
            title: "Thùng rác",
            scope: .system,
            relativePaths: [".Trash"],
            caution: "Dữ liệu trong Thùng rác sẽ bị xoá vĩnh viễn, không thể khôi phục"
        ),
    ]

    /// Subpaths under Library/Caches that belong to specialized developer categories and must be skipped
    /// in the general user cache category to avoid double counting.
    public static let devCacheSubpaths: Set<String> = [
        "org.swift.swiftpm",
        "CocoaPods",
        "Homebrew"
    ]
}
