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

/// What clicking a card (or pressing Return) does. Paste is the default; a value stored by a user who chose copy is kept.
nonisolated enum ClickAction: String, Codable, Sendable, CaseIterable {
    case copy, paste
}

/// Setting names and defaults in one place, shared by the running module and the Settings rows.
struct ClipboardSettingKeys {
    static let historyLimitRange = 50...5000
    static let imageStorageLimitMBRange = 50...2000
    static let boardLockIdleMinutesRange = 1...240
    /// Shared with `ClipboardRetentionKeys`, so the rule that runs while the module is off is the one the rows show.
    static let historyLimitDefault = 500
    static let retentionDefault = Retention.month
    static let imageStorageLimitMBDefault = 250

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
    /// Whether the library's inspector pane is shown (⌘I).
    let libraryInspectorVisible: SettingKey<Bool>
    /// The floating panel stays open after an action and can be moved.
    let panelPinned: SettingKey<Bool>
    /// Where a pinned panel was left; nil until one is pinned.
    let panelPosition: SettingKey<ClipboardPanelPosition?>
    /// Which copy the stack pastes next.
    let stackOrder: SettingKey<CopyStackOrder>
    /// Whether the stack is written to disk and comes back after a restart. Off by default: a stack is short-lived and
    /// may hold secrets.
    let stackPersist: SettingKey<Bool>
    /// Whether AI agents may search the history through the MCP helper. Off by default: it hands out what the user copied.
    let mcpEnabled: SettingKey<Bool>
    /// Minutes without using an open locked board before it closes again.
    let boardLockIdleMinutes: SettingKey<Int>
    /// Whether open locked boards also close when the notch does. Off by default: a paste closes the notch, which would close the
    /// board after every item taken from it.
    let boardLockOnNotchClose: SettingKey<Bool>
    /// A short, quiet sound when an item is captured and when MyNotch pastes one. Off by default.
    let playSounds: SettingKey<Bool>
    /// Whether a link's page is opened to read its title and picture. Off by default: it is the one thing the module does on the
    /// network, and it tells the page's server that someone looked at the link.
    let linkPreviews: SettingKey<Bool>

    init(_ settings: ModuleSettings) {
        paused = settings.key("paused", default: false)
        historyLimit = settings.key("historyLimit", default: Self.historyLimitDefault, clampedTo: Self.historyLimitRange)
        retention = settings.key("retention", default: Self.retentionDefault)
        imageStorageLimitMB = settings.key("imageStorageLimitMB", default: Self.imageStorageLimitMBDefault, clampedTo: Self.imageStorageLimitMBRange)
        ignoreSensitive = settings.key("ignoreSensitive", default: true)
        excludedBundleIDs = settings.key("excludedBundleIDs", default: [])
        clickAction = settings.key("clickAction", default: .paste)
        closeAfterAction = settings.key("closeAfterAction", default: true)
        showCopiedActivity = settings.key("showCopiedActivity", default: true)
        colorsWithoutHash = settings.key("colorsWithoutHash", default: true)
        libraryLayout = settings.key("libraryLayout", default: .grid)
        librarySort = settings.key("librarySort", default: .newest)
        libraryCardSize = settings.key("libraryCardSize", default: .medium)
        libraryInspectorVisible = settings.key("libraryInspectorVisible", default: false)
        panelPinned = settings.key("panelPinned", default: false)
        panelPosition = settings.key("panelPosition", default: ClipboardPanelPosition?.none)
        stackOrder = settings.key("stackOrder", default: .firstIn)
        stackPersist = settings.key("stackPersist", default: false)
        mcpEnabled = settings.key("mcpEnabled", default: false)
        boardLockIdleMinutes = settings.key("boardLockIdleMinutes", default: 5, clampedTo: Self.boardLockIdleMinutesRange)
        boardLockOnNotchClose = settings.key("boardLockOnNotchClose", default: false)
        playSounds = settings.key("playSounds", default: false)
        linkPreviews = settings.key("linkPreviews", default: false)
    }
}

/// The three keys of the retention rule, built without a `ModuleSettings` (whose initializer is the registry's): for the daily clean-up
/// when Clipboard has been off since launch and no Settings page has shown its rows yet, so nothing has handed the module its settings.
/// The names are the ones `ModuleSettings` makes (`module.clipboard.<name>`), and a test holds them to `ClipboardSettingKeys`.
enum ClipboardRetentionKeys {
    static let historyLimit = SettingKey<Int>(
        "module.clipboard.historyLimit", default: ClipboardSettingKeys.historyLimitDefault, clampedTo: ClipboardSettingKeys.historyLimitRange
    )
    static let retention = SettingKey<Retention>("module.clipboard.retention", default: ClipboardSettingKeys.retentionDefault)
    static let imageStorageLimitMB = SettingKey<Int>(
        "module.clipboard.imageStorageLimitMB", default: ClipboardSettingKeys.imageStorageLimitMBDefault,
        clampedTo: ClipboardSettingKeys.imageStorageLimitMBRange
    )
}
