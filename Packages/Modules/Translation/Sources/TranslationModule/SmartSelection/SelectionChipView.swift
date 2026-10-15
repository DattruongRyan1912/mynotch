import NotchUI
import SwiftUI

/// What the chip shows and does. Closures, so the chip knows nothing about the module.
struct SelectionChipContent {
    var kind: SelectionHint.Kind
    /// One line, already cut to fit.
    var text: String
    /// "Mở": the notch opens on the Translation tab with the full result.
    var open: @MainActor () -> Void
    /// "Không hiện trong app này"; nil when the app has no bundle ID to remember it by.
    var deny: (@MainActor () -> Void)?
    /// The pointer went over the chip or left it.
    var hover: @MainActor (Bool) -> Void
}

/// The small pill beside a selection: what was understood in one line, "Mở", and a button to stop showing it for this app (a
/// plain button, not a menu: a menu would move the pointer off the chip, which then starts to go away under it). Drawn like
/// the notch, black with the notch's accent. It lives in a panel of its own, which does not inherit the notch's environment,
/// so this hands the interface's accent (the user's choice, or macOS's) down to what draws it.
struct SelectionChipView: View {
    static let maxWidth: CGFloat = 360

    let content: SelectionChipContent
    let interface: NotchInterface

    var body: some View {
        SelectionChipLabel(content: content)
            .environment(\.notchAccent, interface.accent)
            .tint(interface.accent)
    }
}

/// What the chip draws, in the accent its environment gives it.
struct SelectionChipLabel: View {
    let content: SelectionChipContent

    @Environment(\.notchAccent) private var accent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: content.kind == .translation ? "translate" : "arrow.left.arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
            Text(content.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Button(action: content.open) {
                Text("Mở")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AccentLabel.colour(on: accent))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(accent, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Mở kết quả đầy đủ trong tab Dịch")
            if let deny = content.deny {
                Button(action: deny) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NotchTokens.secondaryText)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Không hiện trong app này")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 7)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.14)))
        .frame(maxWidth: SelectionChipView.maxWidth)
    }
}

/// The icon of the live activity beside the collapsed notch.
struct SelectionActivityIcon: View {
    let kind: SelectionHint.Kind

    var body: some View {
        Image(systemName: kind == .translation ? "translate" : "arrow.left.arrow.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(NotchTokens.primaryText)
    }
}

/// A short line in the 64 pt beside the closed notch; two lines at most.
struct SelectionActivityText: View {
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
