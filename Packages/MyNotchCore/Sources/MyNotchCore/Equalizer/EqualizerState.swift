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

    /// What the pipeline applies when the switch is on and the list is empty.
    private static let flatProfile = EQProfile(
        id: UUID(uuid: UUID_NULL), name: "Phẳng", gains: Array(repeating: 0, count: EQProfile.frequencies.count), preamp: 0
    )

    @ObservationIgnored private let settings: SettingsStore
    public private(set) var profiles: [EQProfile]
    public private(set) var selectedID: UUID?
    /// Set by the Âm thanh module while it runs; the Nhạc tab shows its row only then. Not saved.
    public var isAvailable = false
    /// Set by the Âm thanh module: opens its tab. The Nhạc tab calls it.
    public var openEditor: (() -> Void)?

    public init(settings: SettingsStore) {
        self.settings = settings
        profiles = settings.value(Self.profilesKey)?.map { $0.clamped() } ?? EQProfile.defaults()
        let stored = settings.value(Self.selectedKey)
        selectedID = profiles.contains { $0.id == stored } ? stored : profiles.first?.id
        // Seeds the first run, so the ids the selection refers to outlive this launch.
        persist()
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
        profiles.append(profile)
        selectedID = profile.id
        persist()
        return profile
    }

    /// False, and nothing changes, when the name is empty or longer than 40 characters, or the profile does not exist.
    @discardableResult
    public func rename(_ id: UUID, to name: String) -> Bool {
        guard let name = EQProfile.validName(name), let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        profiles[index].name = name
        persist()
        return true
    }

    /// Deleting the selected profile selects the first remaining one, or none.
    public func delete(_ id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles.remove(at: index)
        if selectedID == id { selectedID = profiles.first?.id }
        persist()
    }

    public func setGain(_ value: Double, band: Int) {
        guard EQProfile.frequencies.indices.contains(band) else { return }
        editSelected { $0.gains[band] = EQProfile.clamp(value) }
    }

    public func setPreamp(_ value: Double) {
        editSelected { $0.preamp = EQProfile.clamp(value) }
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
