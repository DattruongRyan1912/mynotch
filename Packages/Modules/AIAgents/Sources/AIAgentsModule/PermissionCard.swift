import AgentHookKit
import AppKit
import NotchUI
import SwiftUI

/// What a permission card says, as text. Pure, so the wording is tested without drawing anything.
nonisolated enum PermissionCardText {
    nonisolated struct Button: Equatable, Sendable {
        let label: String
        let answer: PermissionAnswer

        init(_ label: String, _ answer: PermissionAnswer) {
            self.label = label
            self.answer = answer
        }
    }

    static let buttons = [Button("Cho phép", .allow), Button("Từ chối", .deny), Button("Hỏi trong terminal", .ask)]

    /// The agent and, when the request knows it, the project.
    static func title(of request: PermissionRequest) -> String {
        request.project.map { "\(request.source.displayName) • \($0)" } ?? request.source.displayName
    }

    /// The tool and the short summary of its command or file; never more of the conversation.
    static func detail(of request: PermissionRequest) -> String {
        request.summary.map { "\(request.tool) · \($0)" } ?? request.tool
    }

    /// Nil when nothing waits behind the request on screen.
    static func queued(_ count: Int) -> String? {
        count > 0 ? "+\(count) yêu cầu nữa" : nil
    }
}

/// The request an agent waits on, with the three answers. The same card sits in the strip under the closed notch and
/// at the top of the AI tab. A decision names the exact request it is for, so a click on a card that was just replaced
/// by the next one cannot answer that one.
struct PermissionCard: View {
    /// The strip under the closed notch: it can be at most `NotchGeometry.maxBottomHeight` (80) tall.
    static let stripHeight: CGFloat = 72

    let request: PermissionRequest
    let others: Int
    let decide: (String, PermissionAnswer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: request.source.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange)
                Text(PermissionCardText.title(of: request))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotchTokens.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let queued = PermissionCardText.queued(others) {
                    Text(queued)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NotchTokens.secondaryText)
                        .lineLimit(1)
                }
            }
            Text(PermissionCardText.detail(of: request))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(NotchTokens.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                ForEach(PermissionCardText.buttons, id: \.answer) { button in
                    Button(button.label) { decide(request.id, button.answer) }
                        .buttonStyle(PermissionButtonStyle(tint: Self.tint(of: button.answer)))
                        // The two short answers keep their width; the long one gives way first.
                        .layoutPriority(button.answer == .ask ? 0 : 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private static func tint(of answer: PermissionAnswer) -> Color {
        switch answer {
        case .allow: .green
        case .deny: .red
        case .ask: NotchTokens.secondaryText
        }
    }
}

private struct PermissionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(NotchTokens.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.55 : 0.3)))
            .contentShape(Capsule())
    }
}

/// The short sound that tells the user an agent needs them.
enum AgentAlertSound {
    static func play() {
        NSSound(named: NSSound.Name("Tink"))?.play()
    }
}
