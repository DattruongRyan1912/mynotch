import Foundation
import Observation

/// The equalizer's profiles, the selected one and the switch, shared by the Âm thanh module (which edits them and runs
/// the audio) and the Nhạc tab (which switches between them), so neither module imports the other. Every change is
/// saved at once, so dragging a slider is saving into the selected profile.
@Observable
public final class EqualizerState {
    /// `nil` means the user never had any, so the three defaults are seeded; an empty list means they deleted them all.
    public static let profilesKey = SettingKey<[EQProfile]?>("app.equalizer.profiles", default: nil)
    public static let selectedKey = SettingKey<UUID?>("app.equalizer.selected", default: nil)
    public static let enabledKey = SettingKey<Bool>("app.equalizer.enabled", default: false)
    /// Off by default, so turning the volume down sounds as it always has until the user asks for it.
    public static let loudnessKey = SettingKey<Bool>("app.equalizer.loudness", default: false)
    /// One-time migration key to upgrade legacy negative default preamps (-4, -4, -2) to 0 dB
    public static let defaultPreampMigratedKey = SettingKey<Bool>("migration.equalizer.defaultPreampZeroV1", default: false)
    /// One-time migration key to seed Deep Bass (eqMac) for existing users having default profiles
    public static let deepBassPresetMigratedKey = SettingKey<Bool>("migration.equalizer.deepBassPresetV1", default: false)

    private static let defaultProfileNames: Set<String> = ["Nhạc", "Phim", "Họp", "Deep Bass (eqMac)"]

    /// What the pipeline applies when the switch is on and the list is empty.
    private static let flatProfile = EQProfile(
        id: UUID(uuid: UUID_NULL), name: "Phẳng", gains: Array(repeating: 0, count: EQProfile.frequencies.count), preamp: 0
    )

    @ObservationIgnored public let settings: SettingsStore
    public private(set) var profiles: [EQProfile]
    public private(set) var selectedID: UUID?
    /// Set by the Âm thanh module while it runs; the Nhạc tab shows its row only then. Not saved.
    public var isAvailable = false
    /// Set by the Âm thanh module: opens its tab. The Nhạc tab calls it.
    public var openEditor: (() -> Void)?

    public init(settings: SettingsStore) {
        self.settings = settings
        if let stored = settings.value(Self.profilesKey) {
            var loaded = stored.map { $0.clamped() }
            if !settings.value(Self.defaultPreampMigratedKey) {
                loaded = loaded.map { profile in
                    var p = profile
                    if Self.defaultProfileNames.contains(p.name) && p.preamp < 0 {
                        p.preamp = 0
                    }
                    return p
                }
                settings.set(true, for: Self.defaultPreampMigratedKey)
            }
            if !settings.value(Self.deepBassPresetMigratedKey) {
                let hasDefaultName = loaded.contains { Self.defaultProfileNames.contains($0.name) }
                let alreadyHasDeepBass = loaded.contains { $0.name == "Deep Bass (eqMac)" }
                if hasDefaultName && !alreadyHasDeepBass && !loaded.isEmpty {
                    if let deepBass = EQProfile.defaults().first(where: { $0.name == "Deep Bass (eqMac)" }) {
                        loaded.append(deepBass)
                    }
                }
                settings.set(true, for: Self.deepBassPresetMigratedKey)
            }
            profiles = loaded
        } else {
            profiles = EQProfile.defaults()
            settings.set(true, for: Self.defaultPreampMigratedKey)
            settings.set(true, for: Self.deepBassPresetMigratedKey)
        }
        let stored = settings.value(Self.selectedKey)
        selectedID = profiles.contains { $0.id == stored } ? stored : profiles.first?.id
        // Seeds the first run, so the ids the selection refers to outlive this launch.
        persist()
    }

    /// Reloads profiles and selection from settings store (used when config.toml changes at runtime).
    public func reloadFromSettings() {
        profiles = settings.value(Self.profilesKey)?.map { $0.clamped() } ?? EQProfile.defaults()
        let stored = settings.value(Self.selectedKey)
        selectedID = profiles.contains { $0.id == stored } ? stored : profiles.first?.id
    }

    /// Read through the store, which is observable, so there is one copy of the switch.
    public var isEnabled: Bool {
        get { settings.value(Self.enabledKey) }
        set { settings.set(newValue, for: Self.enabledKey) }
    }

    /// More bass and treble while the device plays quietly; applies only while the EQ is on.
    public var isLoudnessEnabled: Bool {
        get { settings.value(Self.loudnessKey) }
        set { settings.set(newValue, for: Self.loudnessKey) }
    }

    /// Automatically offsets preamp by the peak EQ boost to avoid True-Peak limiter compression.
    public var isAutoHeadroomEnabled: Bool {
        get { settings.value(EqualizerProcessingSettings.autoHeadroomKey) }
        set { settings.set(newValue, for: EqualizerProcessingSettings.autoHeadroomKey) }
    }

    /// True-Peak Limiter Ceiling in dBTP (-1.0, -0.5, 0.0).
    public var ceilingDBTP: Double {
        get { settings.value(EqualizerProcessingSettings.ceilingDBTPKey) }
        set { settings.set(newValue, for: EqualizerProcessingSettings.ceilingDBTPKey) }
    }

    /// Dynamic Loudness Reference Volume (0.10 to 1.00, default 0.60).
    public var loudnessReferenceVolume: Double {
        get { settings.value(EqualizerProcessingSettings.loudnessReferenceVolumeKey) }
        set { settings.set(newValue, for: EqualizerProcessingSettings.loudnessReferenceVolumeKey) }
    }

    /// Dynamic Loudness Maximum Bass Boost in dB (0.0 to 12.0, default 8.5).
    public var loudnessMaxBassDB: Double {
        get { settings.value(EqualizerProcessingSettings.loudnessMaxBassKey) }
        set { settings.set(newValue, for: EqualizerProcessingSettings.loudnessMaxBassKey) }
    }

    /// Dynamic Loudness Maximum Treble Boost in dB (0.0 to 12.0, default 4.0).
    public var loudnessMaxTrebleDB: Double {
        get { settings.value(EqualizerProcessingSettings.loudnessMaxTrebleKey) }
        set { settings.set(newValue, for: EqualizerProcessingSettings.loudnessMaxTrebleKey) }
    }

    public var selected: EQProfile? { profiles.first { $0.id == selectedID } }

    /// What the audio should apply: nil when off, the selected profile, or flat when there is none.
    public var activeProfile: EQProfile? {
        isEnabled ? selected ?? Self.flatProfile : nil
    }

    public func select(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        selectedID = id
        persist()
    }

    /// A copy of the selected profile (or a flat one) under `name`, selected at once. Nil for a bad name.
    @discardableResult
    public func addProfile(named name: String) -> EQProfile? {
        guard let name = EQProfile.validName(name) else { return nil }
        var profile = selected ?? .flat(named: name)
        profile.id = UUID()
        profile.name = name
        profile.isSystem = false
        profiles.append(profile)
        selectedID = profile.id
        persist()
        return profile
    }

    /// False, and nothing changes, when the name is empty or longer than 40 characters, or the profile does not exist or is a system preset.
    @discardableResult
    public func rename(_ id: UUID, to name: String) -> Bool {
        guard let name = EQProfile.validName(name),
              let index = profiles.firstIndex(where: { $0.id == id }),
              canRename(id) else { return false }
        profiles[index].name = name
        persist()
        return true
    }

    /// Deleting a custom profile removes it and selects the first remaining one, or none.
    /// System presets cannot be deleted.
    public func delete(_ id: UUID) {
        guard canDelete(id),
              let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles.remove(at: index)
        if selectedID == id { selectedID = profiles.first?.id }
        persist()
    }

    /// Removes all profiles (used in testing and complete reset).
    public func removeAllProfiles() {
        profiles.removeAll()
        selectedID = nil
        persist()
    }

    public func isSystemDefault(_ id: UUID) -> Bool {
        guard let profile = profiles.first(where: { $0.id == id }) else { return false }
        return EQPresetCatalog.isSystemPreset(profile)
    }

    public func canDelete(_ id: UUID) -> Bool {
        guard let profile = profiles.first(where: { $0.id == id }) else { return false }
        return EQPresetCatalog.canDelete(profile)
    }

    public func canRename(_ id: UUID) -> Bool {
        guard let profile = profiles.first(where: { $0.id == id }) else { return false }
        return EQPresetCatalog.canRename(profile)
    }

    @discardableResult
    public func duplicateProfile(_ id: UUID) -> EQProfile? {
        guard let source = profiles.first(where: { $0.id == id }) else { return nil }
        var baseName = source.name
        if baseName.hasSuffix(" (Bản sao)") {
            baseName = String(baseName.dropLast(" (Bản sao)".count))
        }
        let copySuffix = " (Bản sao)"
        let maxBase = max(1, 40 - copySuffix.count)
        if baseName.count > maxBase {
            baseName = String(baseName.prefix(maxBase))
        }
        var newName = "\(baseName)\(copySuffix)"
        var counter = 2
        while profiles.contains(where: { $0.name == newName }) {
            let numSuffix = " (\(counter))"
            let numMaxBase = max(1, 40 - numSuffix.count)
            let trimmedBase = String(baseName.prefix(numMaxBase))
            newName = "\(trimmedBase)\(numSuffix)"
            counter += 1
            if counter > 9999 { break }
        }
        let copy = EQProfile(
            id: UUID(),
            name: newName,
            gains: source.gains,
            preamp: source.preamp,
            isSystem: false
        )
        profiles.append(copy)
        selectedID = copy.id
        persist()
        return copy
    }

    @discardableResult
    public func addFlatProfile(named name: String = "Phẳng") -> EQProfile? {
        guard let profile = addProfile(named: name) else { return nil }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index].gains = Array(repeating: 0.0, count: EQProfile.frequencies.count)
            profiles[index].preamp = 0.0
            profiles[index].isSystem = false
            persist()
            return profiles[index]
        }
        return profile
    }

    public func resetToDefaults() {
        let factoryDefaults = EQProfile.defaults()
        for defaultProfile in factoryDefaults {
            if let index = profiles.firstIndex(where: { $0.id == defaultProfile.id || ($0.isSystem && $0.name == defaultProfile.name) }) {
                profiles[index].gains = defaultProfile.gains
                profiles[index].preamp = defaultProfile.preamp
                profiles[index].name = defaultProfile.name
                profiles[index].isSystem = true
            } else if !profiles.contains(where: { $0.name == defaultProfile.name && $0.isSystem }) {
                profiles.append(defaultProfile)
            }
        }

        if selectedID == nil || !profiles.contains(where: { $0.id == selectedID }) {
            selectedID = profiles.first?.id
        }

        ceilingDBTP = EqualizerProcessingSettings.defaultCeilingDBTP
        loudnessReferenceVolume = EqualizerProcessingSettings.defaultReferenceVolume
        loudnessMaxBassDB = EqualizerProcessingSettings.defaultMaxBassBoostDB
        loudnessMaxTrebleDB = EqualizerProcessingSettings.defaultMaxTrebleBoostDB
        persist()
    }

    public func setGain(_ value: Double, band: Int) {
        guard EQProfile.frequencies.indices.contains(band) else { return }
        editSelected { $0.gains[band] = EQProfile.clamp(value) }
    }

    public func setPreamp(_ value: Double) {
        editSelected { $0.preamp = EQProfile.clampPreamp(value) }
    }

    public func resetSelectedToFlat() {
        editSelected {
            $0.gains = Array(repeating: 0, count: EQProfile.frequencies.count)
            $0.preamp = 0
        }
    }

    private func editSelected(_ edit: (inout EQProfile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == selectedID }) else { return }
        edit(&profiles[index])
        persist()
    }

    private func persist() {
        settings.set(Optional(profiles), for: Self.profilesKey)
        settings.set(selectedID, for: Self.selectedKey)
    }
}
