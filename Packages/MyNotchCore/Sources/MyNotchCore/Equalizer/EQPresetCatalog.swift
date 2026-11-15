import Foundation

nonisolated public enum EQPresetCatalog {
    public static let systemDefaultNames: Set<String> = [
        "Nhạc",
        "Phim",
        "Họp",
        "Deep Bass (eqMac)"
    ]

    public static func isSystemPreset(_ profile: EQProfile) -> Bool {
        profile.isSystem
    }

    public static func isSystemPreset(name: String) -> Bool {
        systemDefaultNames.contains(name)
    }

    public static func canDelete(_ profile: EQProfile) -> Bool {
        !profile.isSystem
    }

    public static func canRename(_ profile: EQProfile) -> Bool {
        !profile.isSystem
    }
}
