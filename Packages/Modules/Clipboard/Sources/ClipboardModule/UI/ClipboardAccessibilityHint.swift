import NotchUI
import SwiftUI

/// One line over the tab or the library: a click pastes, but Accessibility is not allowed yet, with the button that
/// asks for it. The views show it only while `ClipboardState.needsAccessibility` is set.
struct ClipboardAccessibilityHint: View {
    enum Look {
        /// Light on the notch's black.
        case notch
        /// System colors, for the library window.
        case library
    }

    static let text = "Cần quyền Accessibility để dán trực tiếp"
    static let buttonTitle = "Cấp quyền"

    let look: Look
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(Self.text)
                .foregroundStyle(look == .notch ? NotchTokens.secondaryText : Color.secondary)
                .lineLimit(1)
            button
        }
        .font(.system(size: look == .notch ? 11 : 12))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var button: some View {
        switch look {
        case .notch:
            Button(action: onGrant) {
                Text(Self.buttonTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTokens.primaryText)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(NotchTokens.accent.opacity(0.7), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        case .library:
            Button(Self.buttonTitle, action: onGrant)
                .controlSize(.small)
        }
    }
}
