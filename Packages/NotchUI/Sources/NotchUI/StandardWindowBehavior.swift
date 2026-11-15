import AppKit

public enum StandardWindowBehavior {
    @MainActor
    public static func apply(to window: NSWindow, allowsNativeFullScreen: Bool = false) {
        window.level = .normal
        window.collectionBehavior = allowsNativeFullScreen ? [.fullScreenPrimary] : []
        window.hidesOnDeactivate = false
    }
}
