import CoreGraphics
import MyNotchCore

extension ActivityCenter {
    /// Height the current activity asks for under the collapsed notch; 0 when there is none or it has no strip.
    /// The view and the window controller both read it, so the drawn shape and the hit area cannot disagree.
    var stripHeight: CGFloat {
        guard let activity = current?.activity, activity.hasBottom else { return 0 }
        return activity.bottomHeight
    }
}
