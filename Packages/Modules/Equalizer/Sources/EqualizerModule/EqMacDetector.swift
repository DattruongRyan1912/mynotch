import AppKit

/// eqMac is another EQ on the whole machine. Both on at once means the sound is filtered twice, which the user should know.
enum EqMacDetector {
    static let bundleID = "com.bitgapp.eqmac"

    static func isRunning(among bundleIDs: some Sequence<String?>) -> Bool {
        bundleIDs.contains(bundleID)
    }

    static func isRunning() -> Bool {
        isRunning(among: NSWorkspace.shared.runningApplications.map(\.bundleIdentifier))
    }
}
