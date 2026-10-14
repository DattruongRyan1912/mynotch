import Foundation
import MyNotchCore

/// How long unpinned items are kept.
nonisolated enum Retention: String, Codable, Sendable, CaseIterable {
    case day, week, month, year, forever

    /// nil keeps items forever.
    var interval: TimeInterval? {
        let day: TimeInterval = 24 * 60 * 60
        return switch self {
        case .day: day
        case .week: 7 * day
        case .month: 30 * day
        case .year: 365 * day
        case .forever: nil
        }
    }
}

/// What clicking a card (or pressing Return) does.
nonisolated enum ClickAction: String, Codable, Sendable, CaseIterable {
    case copy, paste
}

/// Setting names and defaults in one place, shared by the running module and the Settings rows.
struct ClipboardSettingKeys {
    static let historyLimitRange = 50...5000
    static let imageStorageLimitMBRange = 50...2000

    let paused: SettingKey<Bool>
    let historyLimit: SettingKey<Int>
    let retention: SettingKey<Retention>
    let imageStorageLimitMB: SettingKey<Int>
    let ignoreSensitive: SettingKey<Bool>
    /// An array rather than a set so equal lists encode to equal bytes.
    let excludedBundleIDs: SettingKey<[String]>
    let clickAction: SettingKey<ClickAction>
    let closeAfterAction: SettingKey<Bool>
    let showCopiedActivity: SettingKey<Bool>
    let colorsWithoutHash: SettingKey<Bool>
    /// How the library window looks; remembered between openings.
    let libraryLayout: SettingKey<ClipboardLibraryLayout>
    let librarySort: SettingKey<ClipboardLibrarySort>
    let libraryCardSize: SettingKey<ClipboardLibraryCardSize>

    init(_ settings: ModuleSettings) {
        paused = settings.key("paused", default: false)
        historyLimit = settings.key("historyLimit", default: 500, clampedTo: Self.historyLimitRange)
        retention = settings.key("retention", default: .month)
        imageStorageLimitMB = settings.key("imageStorageLimitMB", default: 250, clampedTo: Self.imageStorageLimitMBRange)
        ignoreSensitive = settings.key("ignoreSensitive", default: true)
        excludedBundleIDs = settings.key("excludedBundleIDs", default: [])
        clickAction = settings.key("clickAction", default: .copy)
        closeAfterAction = settings.key("closeAfterAction", default: true)
        showCopiedActivity = settings.key("showCopiedActivity", default: true)
        colorsWithoutHash = settings.key("colorsWithoutHash", default: true)
        libraryLayout = settings.key("libraryLayout", default: .grid)
        librarySort = settings.key("librarySort", default: .newest)
        libraryCardSize = settings.key("libraryCardSize", default: .medium)
    }
}
