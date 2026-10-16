import MyNotchCore
import SwiftUI

/// The cat as a live activity: at the lowest priority there is, with a strip under the collapsed notch for it to play on, as wide as the
/// notch and its two wings, and nothing in the wings themselves. The strip is the notch's own mechanism, the one the lyrics use; the
/// cat asks for no width of its own, so the notch is as wide as it is for any activity.
///
/// It is only ever published while nothing else is on the notch (see `PetModule`), so it is never the bubble beside another activity. The
/// `minimal` view and the summary are for the moment between another activity coming and the cat stepping aside.
enum CatActivity {
    /// How tall the strip is: the cat's picture is 24 points, with a point under its feet and one over its ears.
    static let stripHeight: CGFloat = 26

    static func make(stage: CatStage) -> LiveActivity {
        LiveActivity(
            id: PetModule.activityID,
            priority: .low,
            leading: AnyView(Color.clear),
            trailing: AnyView(Color.clear),
            bottom: AnyView(CatStripView(stage: stage).accessibilityHidden(true)),
            bottomHeight: stripHeight,
            minimal: AnyView(
                Image(systemName: "cat.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0xF0 / 255, green: 0xA1 / 255, blue: 0x4E / 255))
                    .accessibilityHidden(true)
            ),
            summary: "Mèo trên notch"
        )
    }
}
