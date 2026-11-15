import ApplicationServices
import Foundation

/// Recovers accessibility permissions when macOS TCC gets into a zombie state after ad-hoc rebuilds or updates.
///
/// Designated requirement changes on ad-hoc signed apps invalidate the previous TCC entry,
/// leaving it visible in System Settings as 'On' while AXIsProcessTrusted() returns false.
/// Resetting the entry via `/usr/bin/tccutil reset Accessibility <bundleID>` clears the zombie state
/// and re-prompts cleanly so the user can re-enable it without manual removal and re-addition.
public struct AccessibilityRecovery: Sendable {
    public typealias ProcessRunner = @Sendable (_ executable: String, _ arguments: [String]) throws -> Void

    public static let defaultRunner: ProcessRunner = { executable, arguments in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "AccessibilityRecovery",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "tccutil failed with exit code \(process.terminationStatus)"]
            )
        }
    }

    public static func reset(
        bundleID: String,
        runner: ProcessRunner = defaultRunner
    ) throws {
        guard !bundleID.isEmpty else { return }
        try runner("/usr/bin/tccutil", ["reset", "Accessibility", bundleID])
    }

    public static func requestPrompt() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func recover(
        bundleID: String,
        runner: ProcessRunner = defaultRunner
    ) async -> Bool {
        do {
            try reset(bundleID: bundleID, runner: runner)
        } catch {
            return false
        }
        // Give TCC daemon a moment to flush the reset entry before prompting
        try? await Task.sleep(for: .milliseconds(800))
        return requestPrompt()
    }
}
