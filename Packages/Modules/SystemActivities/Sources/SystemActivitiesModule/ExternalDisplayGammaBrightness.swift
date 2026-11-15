import CoreGraphics
import Foundation

/// External display brightness control using CoreGraphics Hardware Gamma LUT (CGSetDisplayTransferByTable).
///
/// Modulates the hardware gamma transfer table without needing DDC/CI or external drivers.
/// Clamps brightness to a safe floor of 0.05 to avoid blacking out the screen completely.
nonisolated final class ExternalDisplayGammaBrightness: LevelControlling {
    public typealias DisplaysProvider = @Sendable () -> [CGDirectDisplayID]
    public typealias GammaTableSetter = @Sendable (
        _ display: CGDirectDisplayID,
        _ red: [CGGammaValue],
        _ green: [CGGammaValue],
        _ blue: [CGGammaValue]
    ) -> CGError
    public typealias GammaRestorer = @Sendable () -> Void

    private let activeDisplays: DisplaysProvider
    private let setGammaTable: GammaTableSetter
    private let restoreGamma: GammaRestorer

    private var cachedLevels: [CGDirectDisplayID: Float] = [:]
    private let lock = NSLock()

    static let minSafeLevel: Float = 0.05
    static let maxSafeLevel: Float = 1.0
    static let tableCapacity: Int = 256

    public init(
        activeDisplays: @escaping DisplaysProvider = defaultActiveDisplays,
        setGammaTable: @escaping GammaTableSetter = defaultGammaTableSetter,
        restoreGamma: @escaping GammaRestorer = defaultGammaRestorer
    ) {
        self.activeDisplays = activeDisplays
        self.setGammaTable = setGammaTable
        self.restoreGamma = restoreGamma
    }

    public static let defaultActiveDisplays: DisplaysProvider = {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(displays.count), &displays, &count) == .success else { return [] }
        return displays.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }
    }

    public static let defaultGammaTableSetter: GammaTableSetter = { display, red, green, blue in
        var r = red
        var g = green
        var b = blue
        return CGSetDisplayTransferByTable(display, UInt32(r.count), &r, &g, &b)
    }

    public static let defaultGammaRestorer: GammaRestorer = {
        CGDisplayRestoreColorSyncSettings()
    }

    public func refresh() {
        lock.withLock {
            cachedLevels.removeAll()
        }
    }

    public func read() -> Float? {
        let displays = activeDisplays()
        guard let first = displays.first else { return nil }
        return lock.withLock {
            cachedLevels[first] ?? 1.0
        }
    }

    public func write(_ level: Float) -> Bool {
        let displays = activeDisplays()
        guard !displays.isEmpty else { return false }

        let clamped = min(max(level, Self.minSafeLevel), Self.maxSafeLevel)

        var table = [CGGammaValue](repeating: 0, count: Self.tableCapacity)
        for i in 0..<Self.tableCapacity {
            table[i] = CGGammaValue(Float(i) / Float(Self.tableCapacity - 1) * clamped)
        }

        var anySucceeded = false
        for display in displays {
            let error = setGammaTable(display, table, table, table)
            if error == .success {
                anySucceeded = true
                lock.withLock {
                    cachedLevels[display] = clamped
                }
            }
        }
        return anySucceeded
    }
}
