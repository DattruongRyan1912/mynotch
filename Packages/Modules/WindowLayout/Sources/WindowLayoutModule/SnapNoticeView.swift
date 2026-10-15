import NotchUI
import SwiftUI

/// A line in the notch about a snap that did not turn out as the layout shows, such as a window that cannot be made as
/// small as its zone. Shown through the notch's toast, so it closes by itself.
struct SnapNoticeView: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "rectangle.on.rectangle")
            .font(.callout.weight(.semibold))
            .foregroundStyle(NotchTokens.primaryText)
            .lineLimit(2)
    }
}
