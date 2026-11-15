/// Names the Chrome extension, the native host and the app agree on.
public enum YouTubeBridge {
    /// What the extension passes to `connectNative` and the host manifest's `name` field.
    public static let hostName = "io.lucasvu.mynotch.youtube"

    /// The extension's id, fixed by the public key in its manifest (`Extensions/Chrome/MyNotchYouTube/EXTENSION_ID`;
    /// a test compares the two). The host manifest allows no other origin to start the host.
    public static let extensionID = "cccjddkmjjmnnccbgokidgbkpblogbnp"
}
