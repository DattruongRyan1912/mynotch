import NotchUI
import SwiftUI

/// The rows under the search field while an `@` word is being typed. The keys are the field's, not the list's: up and
/// down move the highlight, Tab and Return complete it, Esc closes the list, so the field keeps the keyboard.
struct ClipboardSuggestionListView: View {
    let look: ClipboardLook
    let list: ClipboardSuggestionList
    let onPick: (Int) -> Void

    private var rowHeight: CGFloat { look == .notch ? 24 : 26 }
    private var visibleRows: Int { look == .notch ? 5 : 8 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(list.items.enumerated()), id: \.element.id) { index, suggestion in
                        row(suggestion, isHighlighted: index == list.highlighted)
                            .id(suggestion.id)
                            .onTapGesture { onPick(index) }
                    }
                }
                .padding(4)
            }
            .scrollIndicators(.never)
            .onChange(of: list.highlighted) {
                if list.items.indices.contains(list.highlighted) { proxy.scrollTo(list.items[list.highlighted].id) }
            }
        }
        .frame(width: look == .notch ? 220 : 260, height: CGFloat(min(list.items.count, visibleRows)) * rowHeight + 8)
        .background(background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Gợi ý bộ lọc")
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: look == .notch ? 10 : 8, style: .continuous)
        switch look {
        case .notch:
            shape.fill(Color(white: 0.16)).overlay { shape.strokeBorder(Color.white.opacity(0.14)) }
                .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
        case .library, .panel:
            shape.fill(.regularMaterial).overlay { shape.strokeBorder(Color.primary.opacity(0.12)) }
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        }
    }

    private func row(_ suggestion: ClipboardSearchSuggestion, isHighlighted: Bool) -> some View {
        HStack(spacing: 6) {
            icon(suggestion.subject)
                .frame(width: 16, height: 16)
            Text(suggestion.title)
                .font(.system(size: look == .notch ? 11 : 12, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(suggestion.token)
                .font(.system(size: look == .notch ? 10 : 11, design: .monospaced))
                .lineLimit(1)
                .opacity(0.7)
        }
        .foregroundStyle(foreground(isHighlighted: isHighlighted))
        .padding(.horizontal, 6)
        .frame(height: rowHeight)
        .background(isHighlighted ? highlight : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(suggestion.title), \(suggestion.token)")
        .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private func icon(_ subject: ClipboardSearchSuggestion.Subject) -> some View {
        switch subject {
        case .kind(let kind):
            Image(systemName: kind.systemImage)
                .font(.system(size: 11))
        case .code:
            Image(systemName: ClipboardSearchTerms.codeSystemImage)
                .font(.system(size: 11))
        case .app(let bundleID):
            if let bundleID, let icon = ClipboardIcons.app(bundleID: bundleID) {
                Image(nsImage: icon)
                    .resizable()
            } else {
                Image(systemName: "app")
                    .font(.system(size: 11))
            }
        }
    }

    private var highlight: Color {
        look == .notch ? NotchTokens.accent.opacity(0.7) : Color.accentColor
    }

    private func foreground(isHighlighted: Bool) -> Color {
        switch look {
        case .notch: NotchTokens.primaryText
        case .library, .panel: isHighlighted ? .white : .primary
        }
    }
}

/// The `@` tokens of the search text that are done, each a chip that removes its token from the text.
struct ClipboardSearchChips: View {
    let look: ClipboardLook
    let tokens: [ClipboardSearchToken]
    let onRemove: (ClipboardSearchToken) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tokens) { token in
                Button { onRemove(token) } label: {
                    HStack(spacing: 4) {
                        Text(token.title)
                            .lineLimit(1)
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .opacity(0.7)
                    }
                    .font(.system(size: look == .notch ? 11 : 12, weight: .medium))
                    .foregroundStyle(look == .notch ? NotchTokens.primaryText : Color.primary)
                    .padding(.horizontal, 8)
                    .frame(height: look == .notch ? 22 : 24)
                    .background(look == .notch ? NotchTokens.accent.opacity(0.45) : Color.accentColor.opacity(0.2), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Bỏ bộ lọc \(token.raw)")
                .accessibilityLabel("Bộ lọc \(token.title)")
                .accessibilityHint("Bấm để bỏ bộ lọc")
            }
        }
    }
}
