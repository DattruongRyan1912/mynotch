import Foundation

nonisolated public enum EqualizerCeilingMode: Double, CaseIterable, Identifiable, Sendable {
    case minusOne = -1.0
    case minusHalf = -0.5
    case zero = 0.0

    public var id: Double { rawValue }

    public var title: String {
        switch self {
        case .minusOne: return "-1.0 dBTP (EBU R128)"
        case .minusHalf: return "-0.5 dBTP (Chuẩn Apple / Mặc định)"
        case .zero: return "0.0 dBTP (Tối đa tuyệt đối)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .minusOne: return "-1.0 dBTP"
        case .minusHalf: return "-0.5 dBTP"
        case .zero: return "0.0 dBTP"
        }
    }
}

nonisolated public enum EqualizerProcessingSettings {
    public static let defaultCeilingDBTP: Double = -0.5
    public static let defaultReferenceVolume: Double = 0.60
    public static let defaultMaxBassBoostDB: Double = 8.5
    public static let defaultMaxTrebleBoostDB: Double = 4.0

    public static let ceilingDBTPKey = SettingKey<Double>("app.equalizer.ceilingDBTP", default: defaultCeilingDBTP)
    public static let loudnessReferenceVolumeKey = SettingKey<Double>("app.equalizer.loudness.refVolume", default: defaultReferenceVolume)
    public static let loudnessMaxBassKey = SettingKey<Double>("app.equalizer.loudness.maxBass", default: defaultMaxBassBoostDB)
    public static let loudnessMaxTrebleKey = SettingKey<Double>("app.equalizer.loudness.maxTreble", default: defaultMaxTrebleBoostDB)
    public static let autoHeadroomKey = SettingKey<Bool>("app.equalizer.autoHeadroom", default: false)
}
