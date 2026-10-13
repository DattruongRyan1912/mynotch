import NotchUI
import SwiftUI

/// Icon beside the closed notch, for the "copied" and hint activities.
struct ClipboardActivityIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(NotchTokens.primaryText)
    }
}

/// Short text beside the closed notch, e.g. "Nhấn ⌘V để dán".
struct ClipboardActivityText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(NotchTokens.primaryText)
            .lineLimit(1)
    }
}

extension ClipboardKind {
    /// SF Symbol for the kind, shared by the activity and the tab.
    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        case .color: "paintpalette"
        }
    }
}
