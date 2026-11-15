import Foundation
import Observation

/// A snapshot of an application with an active CoreAudio playback stream.
nonisolated public struct RunningAudioApp: Identifiable, Hashable, Sendable {
    public let id: String
    public let pid: pid_t
    public let name: String
    public let bundleID: String?
    public let isPlaying: Bool
    public var isControllable: Bool
    public var controlNotice: String?

    public init(
        id: String,
        pid: pid_t,
        name: String,
        bundleID: String? = nil,
        isPlaying: Bool = true,
        isControllable: Bool = true,
        controlNotice: String? = nil
    ) {
        self.id = id
        self.pid = pid
        self.name = name
        self.bundleID = bundleID
        self.isPlaying = isPlaying
        self.isControllable = isControllable
        self.controlNotice = controlNotice
    }
}

/// Persistent volume and mute preferences for a single application.
nonisolated public struct AppVolumeRule: Codable, Equatable, Sendable {
    public var volume: Double
    public var isMuted: Bool

    public init(volume: Double = 1.0, isMuted: Bool = false) {
        let safe = volume.isFinite ? volume : 1.0
        self.volume = min(max(safe, 0.0), 1.5)
        self.isMuted = isMuted
    }
}

/// Observable state managing per-application audio levels and mute rules across the system.
@Observable
@MainActor
public final class AppVolumeState {
    public static let rulesKey = SettingKey<[String: AppVolumeRule]>("app.volume.rules", default: [:])

    @ObservationIgnored private let settings: SettingsStore
    public private(set) var rules: [String: AppVolumeRule] = [:]
    public var runningApps: [RunningAudioApp] = []

    public init(settings: SettingsStore) {
        self.settings = settings
        self.rules = settings.value(Self.rulesKey)
    }

    public func rule(for appID: String) -> AppVolumeRule {
        rules[appID] ?? AppVolumeRule(volume: 1.0, isMuted: false)
    }

    /// Effective volume: 0.0 if application is muted, otherwise its configured volume (0.0 ... 1.5).
    public func volume(for appID: String) -> Double {
        let r = rule(for: appID)
        return r.isMuted ? 0.0 : r.volume
    }

    /// Saved volume setting regardless of mute state.
    public func rawVolume(for appID: String) -> Double {
        rule(for: appID).volume
    }

    public func isMuted(for appID: String) -> Bool {
        rule(for: appID).isMuted
    }

    public func setVolume(_ volume: Double, for appID: String) {
        guard volume.isFinite else { return }
        let clamped = min(max(volume, 0.0), 1.5)
        var current = rule(for: appID)
        current.volume = clamped
        rules[appID] = current
        settings.set(rules, for: Self.rulesKey)
    }

    public func setMuted(_ muted: Bool, for appID: String) {
        var current = rule(for: appID)
        current.isMuted = muted
        rules[appID] = current
        settings.set(rules, for: Self.rulesKey)
    }

    public func toggleMute(for appID: String) {
        var current = rule(for: appID)
        current.isMuted.toggle()
        rules[appID] = current
        settings.set(rules, for: Self.rulesKey)
    }

    public func reset(for appID: String) {
        rules[appID] = AppVolumeRule(volume: 1.0, isMuted: false)
        settings.set(rules, for: Self.rulesKey)
    }

    public func resetAll() {
        rules.removeAll()
        settings.set(rules, for: Self.rulesKey)
    }

    @ObservationIgnored private var notices: [String: String] = [:]

    public func setControlNotice(_ notice: String?, for appID: String) {
        if let notice = notice {
            notices[appID] = notice
        } else {
            notices.removeValue(forKey: appID)
        }
        for index in runningApps.indices where runningApps[index].id == appID {
            runningApps[index].controlNotice = notice
        }
    }

    public func controlNotice(for appID: String) -> String? {
        notices[appID]
    }

    public func updateRunningApps(_ apps: [RunningAudioApp]) {
        var seen = Set<String>()
        var unique: [RunningAudioApp] = []
        for var app in apps {
            if seen.insert(app.id).inserted {
                if let savedNotice = notices[app.id] {
                    app.controlNotice = savedNotice
                }
                unique.append(app)
            }
        }
        self.runningApps = unique
    }
}
