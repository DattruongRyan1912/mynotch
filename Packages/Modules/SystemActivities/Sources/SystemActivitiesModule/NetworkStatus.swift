/// What the system activity needs to know about the current network path.
nonisolated struct NetworkStatus: Equatable, Sendable {
    enum Interface: Equatable, Sendable { case wifi, ethernet, cellular, other, none }

    var isConnected: Bool
    var interface: Interface
    var isExpensive: Bool

    /// Whether the user would notice the change; the expensive flag alone is not worth an activity.
    func differs(from other: NetworkStatus) -> Bool {
        isConnected != other.isConnected || interface != other.interface
    }
}
