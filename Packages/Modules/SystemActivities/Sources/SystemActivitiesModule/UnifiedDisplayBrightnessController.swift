import Foundation

/// Combines built-in display brightness (via DisplayServices) and external monitor brightness (via Gamma LUT).
///
/// If a built-in display is active and controllable, it receives brightness adjustments.
/// When the Mac is running with external displays only (clamshell mode, Mac mini, Mac Studio, Mac Pro),
/// adjustments seamlessly route to external monitors via hardware gamma ramp.
nonisolated final class UnifiedDisplayBrightnessController: LevelControlling {
    public enum ActiveDisplayKind: Sendable {
        case builtIn
        case external
    }

    private let builtIn: any LevelControlling
    private let external: any LevelControlling
    private let kindChooser: (() -> ActiveDisplayKind)?

    public init(
        builtIn: any LevelControlling,
        external: any LevelControlling,
        kindChooser: (() -> ActiveDisplayKind)? = nil
    ) {
        self.builtIn = builtIn
        self.external = external
        self.kindChooser = kindChooser
    }

    private func currentKind() -> ActiveDisplayKind {
        if let kindChooser { return kindChooser() }
        return builtIn.read() != nil ? .builtIn : .external
    }

    public func refresh() {
        builtIn.refresh()
        external.refresh()
    }

    public func read() -> Float? {
        switch currentKind() {
        case .builtIn:
            return builtIn.read() ?? external.read()
        case .external:
            return external.read() ?? builtIn.read()
        }
    }

    public func write(_ level: Float) -> Bool {
        switch currentKind() {
        case .builtIn:
            if builtIn.write(level) { return true }
            return external.write(level)
        case .external:
            if external.write(level) { return true }
            return builtIn.write(level)
        }
    }
}
