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

/// "Press ⌘V" in the 64 pt beside the closed notch, after a paste that lacked the Accessibility permission.
struct ClipboardPasteKeyHint: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "keyboard")
            Text("⌘V")
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(NotchTokens.primaryText)
        .lineLimit(1)
        .fixedSize()
    }
}

/// A short message over the open tab; activities would stay hidden until the notch closes.
struct ClipboardToast: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout.weight(.semibold))
            .foregroundStyle(NotchTokens.primaryText)
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
