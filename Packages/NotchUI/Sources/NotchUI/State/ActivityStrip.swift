import CoreGraphics
import MyNotchCore

extension NotchViewModel {
    /// The width the current activity's strip asked for, 0 when it has no strip or has not asked. Every reader of the collapsed notch's
    /// width (the view, the window controller's hit area) reads it here, so the drawn shape and the hit area cannot disagree. It does not
    /// depend on the list: the notch stays as wide as its strip while the list of activities is open under it, so the bubbles, which are
    /// what the pointer hovers to open it, stay where they are.
    func stripWidth(of activities: ActivityCenter) -> CGFloat {
        activities.stripHeight > 0 || activities.currentHasBody ? stripWidth(for: activities.current?.id) : 0
    }
}

extension ActivityCenter {
    /// Whether the current activity draws across the top row of the collapsed notch (`LiveActivity.body`). Such an activity asks for the
    /// notch's width like a strip does, with or without a strip.
    var currentHasBody: Bool { current?.activity.hasBody ?? false }

    /// Height the current activity asks for under the collapsed notch; 0 when there is none or it has no strip.
    /// The view and the window controller both read it, so the drawn shape and the hit area cannot disagree.
    var stripHeight: CGFloat {
        guard let activity = current?.activity, activity.hasBottom else { return 0 }
        return activity.bottomHeight
    }
}
