import Foundation
import IOKit.ps

/// Source of battery readings; faked in tests.
public protocol PowerSourceReading: AnyObject {
    func read() -> PowerSourceSnapshot?
    /// What the battery's own registry entry adds (cycles, capacity, power, adapter); nil when it cannot be read.
    func readDetails() -> BatteryDetails?
    /// Low Power Mode is a setting of the Mac rather than of the power source, but the tab shows it with the battery.
    var isLowPowerModeEnabled: Bool { get }
    /// Calls onChange whenever macOS reports a power source change or Low Power Mode is switched, until stopObserving().
    /// Returns false if power source notifications are unavailable.
    @discardableResult func startObserving(_ onChange: @escaping @MainActor () -> Void) -> Bool
    func stopObserving()
}

/// Reads the internal battery through IOKit: the power source API for the level and the times, the battery's
/// registry entry for the rest.
public final class IOKitPowerSource: PowerSourceReading {
    /// Created once and only added to / removed from the run loop: recreating it leaks a mach port each time.
    private var runLoopSource: CFRunLoopSource?
    private var isObserving = false
    private var onChange: (@MainActor () -> Void)?
    private let lowPowerMode = LowPowerModeObserver()

    public init() {}

    isolated deinit {
        stopObserving()
        if let runLoopSource { CFRunLoopSourceInvalidate(runLoopSource) }
    }

    public func read() -> PowerSourceSnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        let descriptions = list.compactMap { source in
            IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        }
        let registry = AppleSmartBatteryRegistry.properties()
        let adapterDetails = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue()
        let hasAdapterDetails = adapterDetails != nil
        return PowerSourceParser.parse(
            descriptions,
            registryProperties: registry,
            hasExternalAdapterDetails: hasAdapterDetails
        )
    }

    public func readDetails() -> BatteryDetails? {
        AppleSmartBatteryRegistry.properties().map(BatteryDetailsParser.parse)
    }

    public var isLowPowerModeEnabled: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    @discardableResult
    public func startObserving(_ onChange: @escaping @MainActor () -> Void) -> Bool {
        stopObserving()
        self.onChange = onChange
        lowPowerMode.start { [weak self] in self?.onChange?() }
        if runLoopSource == nil {
            let context = Unmanaged.passUnretained(self).toOpaque()
            runLoopSource = IOPSNotificationCreateRunLoopSource({ context in
                guard let context else { return }
                let reader = Unmanaged<IOKitPowerSource>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { reader.onChange?() }
            }, context)?.takeRetainedValue()
        }
        guard let runLoopSource else { return false }
        // Common modes keep updates flowing while a menu is open (event-tracking mode).
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        isObserving = true
        return true
    }

    public func stopObserving() {
        if isObserving, let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        isObserving = false
        lowPowerMode.stop()
        onChange = nil
    }
}
