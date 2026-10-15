import Foundation

/// The limits that protect the clipboard history and the agent's context. The helper and the app both read them here, so
/// they cannot drift apart.
public enum ClipboardMCPLimits {
    /// Characters of a search text.
    public static let maxQueryLength = 500
    /// Characters of the `app` filter, which is a name.
    public static let maxAppLength = 100
    public static let defaultResultLimit = 10
    public static let maxResultLimit = 50
    /// "Since N days": ten years is already more than the history keeps.
    public static let maxSinceDays = 3650
    /// UTF-8 bytes of one item's text; the rest is cut and the item says so.
    public static let maxTextBytes = 8 * 1024
    /// UTF-8 bytes of text over all the items of one answer: fifty items of 8 KB are 400 KB, which is more than an agent
    /// wants in its context. Items that would pass it are left out and the answer says so.
    public static let maxTotalTextBytes = 128 * 1024
    public static let maxCallsPerSecond = 10
}
