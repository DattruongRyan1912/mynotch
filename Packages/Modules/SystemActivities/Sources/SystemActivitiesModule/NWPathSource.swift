import Network

/// Reads network paths from `NWPathMonitor`.
final class NWPathSource: PathSource {
    private var monitor: NWPathMonitor?

    init() {}

    func start(_ onUpdate: @escaping @MainActor (NetworkStatus) -> Void) {
        stop()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let status = NetworkStatus(path)
            MainActor.assumeIsolated { onUpdate(status) }
        }
        monitor.start(queue: .main)
        self.monitor = monitor
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }
}

private extension NetworkStatus {
    nonisolated init(_ path: NWPath) {
        let interface: Interface
        if path.status != .satisfied {
            interface = .none
        } else if path.usesInterfaceType(.wifi) {
            interface = .wifi
        } else if path.usesInterfaceType(.wiredEthernet) {
            interface = .ethernet
        } else if path.usesInterfaceType(.cellular) {
            interface = .cellular
        } else {
            interface = .other
        }
        self.init(isConnected: path.status == .satisfied, interface: interface, isExpensive: path.isExpensive)
    }
}
