import NotchUI
import SwiftUI

/// Icon in the 64 pt beside the closed notch.
struct ShortcutActivityIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(NotchTokens.primaryText)
    }
}

/// A short line beside the closed notch; two lines at most.
struct ShortcutActivityText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(NotchTokens.primaryText)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// What a shortcut returned, over the open tab, with a button to copy all of it.
struct ShortcutOutputToast: View {
    /// The toast shows four lines, so a long output is cut well before layout has to measure all of it. Copying
    /// still gives the whole text.
    static let previewLimit = 600

    static func preview(of text: String) -> String {
        text.dropFirst(previewLimit).isEmpty ? text : String(text.prefix(previewLimit)) + "…"
    }

    let text: String
    let copy: () -> Void

    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            Text(Self.preview(of: text))
                .font(.callout)
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(4)
                .frame(maxWidth: 320, alignment: .leading)
            Button(copied ? "Đã chép" : "Chép", systemImage: copied ? "checkmark" : "doc.on.doc") {
                copy()
                copied = true
            }
            .buttonStyle(.bordered)
        }
    }
}
