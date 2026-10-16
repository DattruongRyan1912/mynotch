/// The names the app, the launchd plist and the helper must agree on. A test pins each against the plist in the repo.
public enum FanHelperIdentity {
    /// The mach service the helper listens on, and the launchd job's label; the plist is named after it.
    public static let machServiceName = "io.lucasvu.mynotch.fanhelper"
    public static let plistName = "io.lucasvu.mynotch.fanhelper.plist"
    /// Where the helper is inside the app's bundle, which is what the plist's `BundleProgram` says.
    public static let helperProgram = "Contents/MacOS/mynotch-fan-helper"

    public static let appIdentifier = "io.lucasvu.mynotch"
    /// Xcode signs a command-line tool with its product name as the code-signing identifier.
    public static let helperIdentifier = "mynotch-fan-helper"
    public static let teamIdentifier = "B394MAY4QN"

    /// Bumped by hand when the helper's behaviour or its launchd plist changes without the executable changing in a way a build
    /// would show: the build id (the code directory hash) changes with every build, the plist is not part of it.
    public static let version = "1"
}
