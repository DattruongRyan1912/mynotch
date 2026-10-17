import SwiftUI

/// What a strip under the collapsed notch tells the notch about the width it wants.
struct NotchStripWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Tells the notch how wide this strip wants to be, in points: the width of what it shows, without the notch's own padding. Put it
    /// on the view an activity gives as its `bottom`. While the strip is under the collapsed notch, the notch is as wide as the strip
    /// wants and the padding take (`NotchGeometry.compactWidth(stripWidth:)`), never narrower than it is without a strip and never
    /// wider than `NotchGeometry.maximumStripWidth`, and it grows and shrinks with the notch's spring, about its centre. A strip that does not
    /// say keeps the notch's width as it was.
    public func notchStripWidth(_ width: CGFloat) -> some View {
        preference(key: NotchStripWidthKey.self, value: width)
    }
}

extension View {
    /// Tells the notch how wide the row this view fills wants to be, in points: for the `body` of a live activity, which is drawn across the
    /// whole top row of the collapsed notch, between the ears. The notch is as wide as that row and its ears, between what it is without a
    /// body and `NotchGeometry.maximumStripWidth`, with the notch's spring and about its centre, while the activity is the current one; it
    /// goes the way a strip's width goes (`notchStripWidth`), hysteresis and all. A body that asks for nothing keeps the notch's width.
    public func notchBodyWidth(_ width: CGFloat) -> some View {
        notchStripWidth(max(width - 2 * NotchTokens.stripPadding, 0))
    }
}

extension View {
    /// Calls `action` with the width a strip inside this view asks for (`notchStripWidth`), for whatever hosts a strip outside the notch
    /// and for a test; the notch itself listens in its own way.
    public func onNotchStripWidth(perform action: @escaping (CGFloat) -> Void) -> some View {
        onPreferenceChange(NotchStripWidthKey.self, perform: action)
    }
}

/// How a strip's reported width settles in the notch.
nonisolated enum StripWidth {
    /// A new width narrower than the one in use by less than this is ignored, so lines that are about as wide as each other do not make the
    /// notch breathe. Wider is always taken.
    static let shrinkThreshold: CGFloat = 24

    /// The width to use when `reported` comes in and `current` is in use (nil for none yet).
    static func settle(current: CGFloat?, reported: CGFloat) -> CGFloat {
        guard let current else { return reported }
        return reported >= current || current - reported >= shrinkThreshold ? reported : current
    }
}
