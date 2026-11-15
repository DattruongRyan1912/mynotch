import CoreGraphics
import Foundation

/// Measurements of the battery drawn across the tab, and where its number goes.
nonisolated struct BatteryGaugeLayout: Equatable {
    static let height: CGFloat = 46
    static let cornerRadius: CGFloat = 12
    static let outlineWidth: CGFloat = 2
    /// Between the outline and the fill.
    static let inset: CGFloat = 3
    static let nubSize = CGSize(width: 4, height: 16)
    /// Free space on either side of the number, inside the fill or beside it.
    static let labelMargin: CGFloat = 10

    /// Concentric with the outline, so the fill follows the body's corners.
    static let fillRadius = cornerRadius - outlineWidth - inset
    /// Two radii: the narrowest the fill can be and still look like a fill.
    static let minimumFillWidth = 2 * fillRadius

    /// Where the fill and the track live: the body without outline and inset.
    let innerWidth: CGFloat
    let fillWidth: CGFloat

    init(percent: Int, bodyWidth: CGFloat) {
        innerWidth = max(0, bodyWidth - 2 * (Self.outlineWidth + Self.inset))
        let proportional = innerWidth * CGFloat(min(max(percent, 0), 100)) / 100
        // A battery with anything left keeps a visible sliver.
        fillWidth = percent > 0 ? min(innerWidth, max(proportional, Self.minimumFillWidth)) : 0
    }

    /// Black on the fill only when the number has its margins inside it; otherwise it sits beside the fill.
    func labelFitsInside(labelWidth: CGFloat) -> Bool {
        fillWidth >= labelWidth + 2 * Self.labelMargin
    }

    /// Where the number starts, measured from the left end of the fill.
    func labelOffset(labelWidth: CGFloat) -> CGFloat {
        labelFitsInside(labelWidth: labelWidth) ? fillWidth - labelWidth - Self.labelMargin : fillWidth + Self.labelMargin
    }
}

/// The one motion of the tab: a highlight sweeping across the fill while it charges.
nonisolated enum BatteryGaugeMotion {
    static let sweepPeriod: TimeInterval = 2.6

    /// Only while it can be seen: charging, the tab open, the notch's window on screen (not hidden by a fullscreen app, a locked screen or
    /// a display asleep), and motion allowed. Anywhere else the animation is not even added, so the render server carries nothing.
    static func isSweeping(isCharging: Bool, isTabVisible: Bool, isOnScreen: Bool, reduceMotion: Bool) -> Bool {
        isCharging && isTabVisible && isOnScreen && !reduceMotion
    }

    /// 0 at the left end of the fill and 1 past its right end, repeating every `sweepPeriod`.
    static func sweepPhase(at time: TimeInterval) -> Double {
        time.truncatingRemainder(dividingBy: sweepPeriod) / sweepPeriod
    }

    /// Whether to display AC passthrough plug icon on the battery gauge (adapter connected, not charging cell, not forced discharging).
    static func showsPlug(isCharging: Bool, isAttachedToAdapter: Bool, isDischargeActive: Bool) -> Bool {
        isAttachedToAdapter && !isCharging && !isDischargeActive
    }
}
