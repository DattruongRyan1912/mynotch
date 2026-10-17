import MyNotchCore
import SwiftUI

/// The cat as a live activity: at the lowest priority there is, playing in the top row of the collapsed notch (its `body`: beside the
/// camera of a hardware notch, through a portal from one side to the other, and across a virtual notch), or, if the user chose it, on a
/// strip under a hardware notch, as wide as the notch and its two wings (the notch's own mechanism, the one the lyrics use). A virtual
/// notch has room in its body, so it never gets the strip.
///
/// It is only ever published while nothing else is on the notch (see `PetModule`), so it is never the bubble beside another activity. The
/// `minimal` view and the summary are for the moment between another activity coming and the cat stepping aside.
enum CatActivity {
    /// How tall the strip is: the cat's picture is 24 points, with a point under its feet and one over its ears.
    static let stripHeight: CGFloat = 26

    static func make(stage: CatStage, place: PlayPlace = .portal) -> LiveActivity {
        LiveActivity(
            id: PetModule.activityID,
            priority: .low,
            leading: AnyView(Color.clear),
            trailing: AnyView(Color.clear),
            bottom: place == .strip ? AnyView(CatStripView(stage: stage).accessibilityHidden(true)) : nil,
            bottomHeight: place == .strip ? stripHeight : 0,
            bottomScope: .hardwareNotchOnly,
            body: AnyView(CatBodyView(stage: stage, place: place).accessibilityHidden(true)),
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
