import AppKit
import MyNotchCore
import NotchUI
import SwiftUI

/// A short message about what happened to the menu bar: on the notch, where the eye already is, and announced to
/// VoiceOver, because a beep alone says nothing to a muted Mac or to someone who cannot see the menu bar.
final class MenuBarNotice {
    private let presenter: any NotchPresenter

    init(presenter: any NotchPresenter) {
        self.presenter = presenter
    }

    func show(_ text: String) {
        presenter.showToast(AnyView(MenuBarNoticeView(text: text)), duration: .seconds(4))
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }
}

private struct MenuBarNoticeView: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.callout.weight(.semibold))
            .foregroundStyle(NotchTokens.primaryText)
            .multilineTextAlignment(.center)
            .lineLimit(2)
    }
}
