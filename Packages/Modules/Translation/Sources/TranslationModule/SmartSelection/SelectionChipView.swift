import NotchUI
import SwiftUI

/// What the chip shows and does. Closures, so the chip knows nothing about the module.
struct SelectionChipContent {
    var kind: SelectionHint.Kind
    /// A conversion: one line, already cut to fit. A translation: all of it, which the chip wraps and scrolls. A button: its
    /// note, or empty.
    var text: String
    /// What the button says: "Mở" for a result, "Dịch" when there is no preview to show and the tab does the translating.
    var actionTitle = "Mở"
    /// The first line of the original, small, over a translation; nil when there is none to show.
    var caption: String?
    /// Beside the button, small: "Mở để dịch đủ" when only the start of a long selection was translated.
    var note: String?
    /// The button: the notch opens on the Translation tab with the full result.
    var open: @MainActor () -> Void
    /// "Không hiện trong app này", from the "⋯" menu; nil when the app has no bundle ID to remember it by.
    var deny: (@MainActor () -> Void)?
    /// The pointer went over the chip or left it (or a menu of the chip opened or closed).
    var hover: @MainActor (Bool) -> Void
}

/// The pill beside a selection. A conversion or a button is one compact line; a translation is shown whole, wrapped, in a chip
/// that grows with it and scrolls inside past about eight lines, with the first line of the original over it. Drawn like the
/// notch, black with the notch's accent. It lives in a panel of its own, which does not inherit the notch's environment, so
/// this hands the interface's accent (the user's choice, or macOS's) down to what draws it.
struct SelectionChipView: View {
    static let maxWidth = SelectionChipLayout.maxWidth

    let content: SelectionChipContent
    let interface: NotchInterface
    /// The most the chip may take: the room beside the selection, so it never covers it.
    var maxHeight = SelectionChipLayout.maxHeight

    var body: some View {
        SelectionChipLabel(content: content, maxHeight: maxHeight)
            .environment(\.notchAccent, interface.accent)
            .tint(interface.accent)
            // The chip is black whatever the look, so the text tokens must be the light ones even where they follow the glass.
            .notchOnDarkBackground()
    }
}

/// What the chip draws, in the accent its environment gives it.
struct SelectionChipLabel: View {
    let content: SelectionChipContent
    var maxHeight = SelectionChipLayout.maxHeight

    @Environment(\.notchAccent) private var accent

    var body: some View {
        Group {
            // With less room beside the selection than the smallest translation chip, the compact line, which fits anywhere.
            if content.kind == .translation, maxHeight >= SelectionChipLayout.minChipHeight { wholeTranslation } else { compactLine }
        }
        .background(Color.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.14)))
    }

    private var icon: some View {
        Image(systemName: content.kind == .conversion ? "arrow.left.arrow.right" : "translate")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(accent)
    }

    /// The button that opens the tab.
    private var action: some View {
        Button(action: content.open) {
            Text(content.actionTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AccentLabel.colour(on: accent))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(accent, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(content.kind == .button ? "Dịch trong tab Dịch" : "Mở kết quả đầy đủ trong tab Dịch")
    }

    /// Hiding the app is asked from a menu, not a button: it is easy to hit by accident, and it takes the chip away for good.
    @ViewBuilder private var hideMenu: some View {
        if let deny = content.deny {
            Menu {
                Button("Không hiện trong app này", action: deny)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTokens.secondaryText)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    /// What the compact line says: a translation squeezed in here gives its first line, which "Mở" shows in full.
    private var compactText: String {
        content.kind == .translation ? SelectionHint.firstLine(of: content.text) ?? content.text : content.text
    }

    /// A conversion, or a button: an icon, what was understood in one line, the button and the menu.
    private var compactLine: some View {
        HStack(spacing: 8) {
            icon
            if !compactText.isEmpty {
                Text(compactText)
                    .font(.system(size: 12, weight: .medium))
                    // A button's note is a reason, not a result.
                    .foregroundStyle(content.kind == .button ? NotchTokens.secondaryText : NotchTokens.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            action
            hideMenu
        }
        .padding(.leading, 10)
        .padding(.trailing, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: SelectionChipLayout.maxWidth)
    }

    /// A translation: the first line of the original over it, then all of it, then the button and the menu.
    private var wholeTranslation: some View {
        let metrics = SelectionChipLayout.metrics(for: content.text, caption: content.caption, maxHeight: maxHeight)
        return VStack(alignment: .leading, spacing: 4) {
            if metrics.showsCaption, let caption = content.caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(NotchTokens.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: metrics.textWidth, height: SelectionChipLayout.captionHeight - 4, alignment: .leading)
            }
            ScrollView(.vertical) {
                Text(content.text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NotchTokens.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: metrics.textWidth, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: metrics.textWidth, height: metrics.textHeight)
            HStack(spacing: 8) {
                icon
                if let note = content.note {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(NotchTokens.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                action
                hideMenu
            }
            .frame(width: metrics.textWidth, height: 24)
        }
        .padding(.horizontal, SelectionChipLayout.sidePadding)
        .padding(.vertical, 10)
    }
}

/// The icon of the live activity beside the collapsed notch.
struct SelectionActivityIcon: View {
    let kind: SelectionHint.Kind

    var body: some View {
        Image(systemName: kind == .conversion ? "arrow.left.arrow.right" : "translate")
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

/// The notice shown once per run of the app when a selection is made and MyNotch has no Accessibility permission: without it
/// nothing can be read, and silence looks like a broken feature. Over the notch, so it uses the accent the notch gives it.
struct SelectionAccessibilityNotice: View {
    let grant: () -> Void

    @Environment(\.notchAccent) private var accent

    var body: some View {
        HStack(spacing: 10) {
            Label("Bôi đen là hiểu cần quyền Trợ năng", systemImage: "hand.raised.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(2)
            Button(action: grant) {
                Text("Cấp quyền")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AccentLabel.colour(on: accent))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accent, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

/// The notice after an app was hidden from the chip: what was done, and the way back for a few seconds.
struct SelectionDenialNotice: View {
    let appName: String
    let undo: () -> Void
    /// The notice left the screen, so there is no button any more to undo with.
    let gone: () -> Void

    @Environment(\.notchAccent) private var accent

    static func title(appName: String) -> String { "Đã ẩn trong \(appName)" }

    var body: some View {
        HStack(spacing: 10) {
            Label(Self.title(appName: appName), systemImage: "eye.slash")
                .font(.callout.weight(.semibold))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(1)
            Button(action: undo) {
                Text("Hoàn tác")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AccentLabel.colour(on: accent))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accent, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .onDisappear(perform: gone)
    }
}
