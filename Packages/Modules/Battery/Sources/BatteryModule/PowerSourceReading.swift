import IOKit.ps

/// Source of battery readings; faked in tests.
public protocol PowerSourceReading: AnyObject {
    func read() -> PowerSourceSnapshot?
    /// Calls `onChange` whenever macOS reports a power source change, until `stopObserving()`.
    func startObserving(_ onChange: @escaping @MainActor () -> Void)
    func stopObserving()
}

/// Reads the internal battery through IOKit power source APIs.
public final class IOKitPowerSource: PowerSourceReading {
    private var runLoopSource: CFRunLoopSource?
    private var onChange: (@MainActor () -> Void)?

    public init() {}

    public func read() -> PowerSourceSnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        let descriptions = list.compactMap { source in
            IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        }
        return PowerSourceParser.parse(descriptions)
    }

    public func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        stopObserving()
        self.onChange = onChange
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let reader = Unmanaged<IOKitPowerSource>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { reader.onChange?() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    public func stopObserving() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode) }
        runLoopSource = nil
        onChange = nil
    }
}
