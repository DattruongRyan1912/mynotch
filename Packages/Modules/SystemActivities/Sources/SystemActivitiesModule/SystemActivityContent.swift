import MyNotchCore

/// What one system activity shows, before it becomes views. Pure, so the wording and symbols are testable.
/// Each kind has a fixed `id`, so a newer event replaces the older one in place.
nonisolated struct SystemActivityContent: Equatable, Sendable {
    enum Glyph: Equatable, Sendable {
        case symbol(String)
        case text(String)
    }

    enum Trailing: Equatable, Sendable {
        case text(String)
        /// 0...1, drawn as a small bar.
        case level(Float)
    }

    var id: String
    var glyph: Glyph
    var trailing: Trailing
    var priority: ActivityPriority = .normal
    /// False for an alert that stays until something replaces it.
    var expires = true

    /// The device's short name only when there is no battery level to show: the side is 64 pt wide.
    static func bluetooth(_ event: BluetoothEvent) -> SystemActivityContent {
        let symbol = switch event.kind {
        case .headphones: "headphones"
        case .keyboard: "keyboard"
        case .mouse: "computermouse"
        case .other: "dot.radiowaves.left.and.right"
        }
        let text = switch (event.connected, event.battery) {
        case (false, _): "Đã ngắt"
        case (true, let battery?): "\(battery.displayPercent)%"
        case (true, nil): String(event.name.prefix(8))
        }
        return SystemActivityContent(id: "bluetooth", glyph: .symbol(symbol), trailing: .text(text))
    }

    static func network(_ status: NetworkStatus) -> SystemActivityContent {
        guard status.isConnected else {
            return SystemActivityContent(
                id: "network", glyph: .symbol("wifi.slash"), trailing: .text("Mất mạng"), priority: .high, expires: false)
        }
        let symbol = switch status.interface {
        case .wifi: "wifi"
        case .ethernet: "cable.connector"
        case .cellular: "antenna.radiowaves.left.and.right"
        case .other, .none: "network"
        }
        return SystemActivityContent(id: "network", glyph: .symbol(symbol), trailing: .text("Đã kết nối"))
    }

    static func capsLock(_ isOn: Bool) -> SystemActivityContent {
        SystemActivityContent(id: "capslock", glyph: .text("⇪"), trailing: .text(isOn ? "Bật" : "Tắt"))
    }

    static func download(_ event: DownloadEvent) -> SystemActivityContent {
        SystemActivityContent(id: "download", glyph: .symbol("arrow.down.circle"), trailing: .text(event.name))
    }

    static func volume(_ state: VolumeState) -> SystemActivityContent {
        let symbol = switch (state.muted || state.level <= 0, state.level) {
        case (true, _): "speaker.slash.fill"
        case (_, ..<0.34): "speaker.wave.1.fill"
        case (_, ..<0.67): "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
        return SystemActivityContent(id: "volume", glyph: .symbol(symbol), trailing: .level(state.muted ? 0 : state.level))
    }
}
