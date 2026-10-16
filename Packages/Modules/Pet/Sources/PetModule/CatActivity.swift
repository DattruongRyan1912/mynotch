import MyNotchCore
import SwiftUI

/// The cat as a live activity: at the lowest priority there is, one view in each wing of the collapsed notch, and no strip under it, so
/// it asks the notch for nothing but the room any activity with nothing to say beneath it asks.
///
/// It is only ever published while nothing else is on the notch (see `PetModule`), so it is never the bubble beside another activity. The
/// `minimal` view and the summary are for the moment between another activity coming and the cat stepping aside.
enum CatActivity {
    static func make(stage: CatStage) -> LiveActivity {
        LiveActivity(
            id: PetModule.activityID,
            priority: .low,
            leading: AnyView(CatWingView(stage: stage, role: .leading).accessibilityHidden(true)),
            trailing: AnyView(CatWingView(stage: stage, role: .trailing).accessibilityHidden(true)),
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
