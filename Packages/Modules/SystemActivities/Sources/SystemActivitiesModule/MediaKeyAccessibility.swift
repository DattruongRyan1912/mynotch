import MyNotchCore
import Observation
import SwiftUI

/// Whether the HUD is on without the Accessibility permission it needs to see the keys, which is what the hint in
/// Settings shows. Reading the permission never prompts; the row checks when it appears and every 2 s while shown, so
/// the hint goes by itself once the permission is allowed.
@Observable
final class MediaKeyAccessibility {
    private(set) var isMissing = false

    @ObservationIgnored private let permissions: any PermissionCenter
    @ObservationIgnored private let isWanted: () -> Bool

    init(permissions: any PermissionCenter, isWanted: @escaping () -> Bool) {
        self.permissions = permissions
        self.isWanted = isWanted
        refresh()
    }

    func refresh() {
        let missing = isWanted() && permissions.status(of: .accessibility) != .granted
        if missing != isMissing { isMissing = missing }
    }

    /// The hint's button: the system's prompt (which lists MyNotch in the Accessibility pane), then that pane when the
    /// prompt alone did not allow it.
    func grant() async {
        if await permissions.request(.accessibility) != .granted {
            permissions.openSystemSettings(for: .accessibility)
        }
        refresh()
    }
}

/// One line under the HUD switch: it needs Accessibility, which is not allowed yet, with the button that asks for it.
struct MediaKeyAccessibilityHint: View {
    static let text = "Cần quyền Accessibility"
    static let buttonTitle = "Cấp quyền"

    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(Self.text)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button(Self.buttonTitle, action: onGrant)
                .controlSize(.small)
        }
        .accessibilityElement(children: .contain)
    }
}
