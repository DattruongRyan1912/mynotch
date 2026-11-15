import Darwin
import Foundation

/// Dispatches heavy disk scanning and deletion on `.utility` QoS with I/O throttling policy.
nonisolated public enum UtilityIO {
    /// Executes a synchronous closure with thread-level disk I/O policy set to utility, restoring default on exit.
    public static func withUtilityPolicy<T>(_ work: () throws -> T) rethrows -> T {
        setiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_THREAD, IOPOL_UTILITY)
        defer {
            setiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_THREAD, IOPOL_DEFAULT)
        }
        return try work()
    }

    /// Queries the current thread-level disk I/O policy.
    public static func currentIOPolicy() -> Int32 {
        getiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_THREAD)
    }

    /// Detaches a background task on `.utility` priority with Darwin I/O disk policy set to IOPOL_UTILITY.
    public static func run<T: Sendable>(_ operation: @Sendable @escaping () throws -> T) async throws -> T {
        try await Task.detached(priority: .utility) {
            try withUtilityPolicy {
                try operation()
            }
        }.value
    }

    /// Detaches a non-throwing background task on `.utility` priority.
    public static func run<T: Sendable>(_ operation: @Sendable @escaping () -> T) async -> T {
        await Task.detached(priority: .utility) {
            withUtilityPolicy {
                operation()
            }
        }.value
    }
}
