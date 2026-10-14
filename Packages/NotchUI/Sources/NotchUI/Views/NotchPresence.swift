import AppKit
import SwiftUI

extension EnvironmentValues {
    /// Whether the window the view is shown in can be seen. A hidden notch (a fullscreen app in front, a locked screen, a display
    /// that sleeps) keeps its views alive, and SwiftUI keeps running their timelines; views that tick read this to stop.
    @Entry public var notchIsOnScreen: Bool = true
}

/// What decides that a notch window counts as on screen.
nonisolated enum NotchPresence {
    /// Ordered in and not entirely hidden. The occlusion state also drops while the display sleeps and the screen is locked.
    static func isOnScreen(isVisible: Bool, occlusion: NSWindow.OcclusionState) -> Bool {
        isVisible && occlusion.contains(.visible)
    }
}

/// A timeline that ticks every `interval` seconds while the notch is on screen, and stands still, showing the content as of
/// the moment it left the screen, while it is not.
public struct NotchTimeline<Content: View>: View {
    @Environment(\.notchIsOnScreen) private var isOnScreen
    private let interval: TimeInterval
    private let content: (Date) -> Content

    public init(every interval: TimeInterval, @ViewBuilder content: @escaping (Date) -> Content) {
        self.interval = interval
        self.content = content
    }

    public var body: some View {
        if isOnScreen {
            TimelineView(.periodic(from: .now, by: interval)) { content($0.date) }
        } else {
            content(.now)
        }
    }
}
