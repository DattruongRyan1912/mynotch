import IOKit.ps

/// Source of battery readings; faked in tests.
public protocol PowerSourceReading: AnyObject {
    func read() -> PowerSourceSnapshot?
    /// Calls onChange whenever macOS reports a power source change, until stopObserving(). Returns false if notifications are unavailable.
    @discardableResult func startObserving(_ onChange: @escaping @MainActor () -> Void) -> Bool
    func stopObserving()
}

/// Reads the internal battery through IOKit power source APIs.
public final class IOKitPowerSource: PowerSourceReading {
    /// Created once and only added to / removed from the run loop: recreating it leaks a mach port each time.
    private var runLoopSource: CFRunLoopSource?
    private var isObserving = false
    private var onChange: (@MainActor () -> Void)?

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
        return PowerSourceParser.parse(descriptions)
    }

    @discardableResult
    public func startObserving(_ onChange: @escaping @MainActor () -> Void) -> Bool {
        stopObserving()
        self.onChange = onChange
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
        onChange = nil
    }
}
