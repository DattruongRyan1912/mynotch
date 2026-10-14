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

    /// Said when the helper gave nothing to show.
    static let placeholder = "(không có chi tiết)"
    /// A tool name longer than this is also written at the head of the scrolling text, since the line it sits on cuts it.
    static let longToolName = 22

    /// "Cho phép" only for a request whose whole text is on the card. Otherwise the answer is given where the whole request
    /// is, in the terminal, and the notch can only deny.
    static func buttons(for request: PermissionRequest) -> [Button] {
        request.canAllow
            ? [Button("Cho phép", .allow), Button("Từ chối", .deny), Button("Hỏi trong terminal", .ask)]
            : [Button("Từ chối", .deny), Button("Trả lời trong terminal", .ask)]
    }

    /// The agent and, when the request knows it, the project.
    static func title(of request: PermissionRequest) -> String {
        request.project.map { "\(request.source.displayName) • \($0)" } ?? request.source.displayName
    }

    static func toolName(of request: PermissionRequest) -> String {
        request.tool
    }

    /// What is asked, as the helper gave it: every line of a command, the whole path, the URL, the arguments or the files
    /// of a patch. A helper that predates the detail gives only its short summary.
    static func body(of request: PermissionRequest) -> String {
        if let detail = request.detail {
            return detail.text.isEmpty ? placeholder : detail.text
        }
        return request.summary.flatMap { $0.isEmpty ? nil : $0 } ?? placeholder
    }

    /// The last line of a request that is not shown whole, at its end: how much was left out.
    static func marker(of request: PermissionRequest) -> String? {
        guard let detail = request.detail else { return request.summary?.isEmpty == false ? incomplete : nil }
        if detail.hiddenLines > 0 { return "… (\(detail.hiddenLines) dòng nữa)" }
        return !detail.isComplete && !detail.text.isEmpty ? incomplete : nil
    }

    private static let incomplete = "… (chưa đủ chi tiết)"

    /// The body and, below it, the marker.
    static func shown(of request: PermissionRequest) -> String {
        [body(of: request), marker(of: request)].compactMap { $0 }.joined(separator: "\n")
    }

    /// What the scroll view holds: `shown`, led by the tool name when that is too long for its own line.
    static func scrolled(of request: PermissionRequest) -> String {
        request.tool.count > longToolName ? request.tool + "\n" + shown(of: request) : shown(of: request)
    }

    /// Said beside the buttons of a request that cannot be allowed here.
    static func notice(of request: PermissionRequest) -> String? {
        request.canAllow ? nil : "Chưa đủ chi tiết để cho phép tại đây"
    }

    /// For VoiceOver: the tool, then every line of what is asked, then how much was left out.
    static func spoken(of request: PermissionRequest) -> String {
        let lines = body(of: request).replacingOccurrences(of: "\n", with: ", ")
        return "\(request.tool): " + [lines, marker(of: request)].compactMap { $0 }.joined(separator: " ")
    }

    /// Nil when nothing waits behind the request on screen.
    static func queued(_ count: Int) -> String? {
        count > 0 ? "+\(count) yêu cầu nữa" : nil
    }
}

/// The request an agent waits on, with its answers. The same card sits in the strip under the closed notch and at the top
/// of the AI tab. The text of what is asked is in a scroll view, whole, and when it cannot be shown whole the card says so
/// and offers no "Cho phép". A card that has just come up, or that took the place of the one before it, takes no answer
/// until its delay is over, and changes visibly when it is replaced, so a click that began on the previous one does not
/// land on this one.
struct PermissionCard: View {
    /// The strip under the closed notch: it can be at most `NotchGeometry.maxBottomHeight` (80) tall.
    static let stripHeight: CGFloat = 80

    enum Placement {
        case strip, tab

        /// Two lines of the text show in the strip, which has no room for more; the tab shows four. The rest scrolls.
        var textHeight: CGFloat {
            switch self {
            case .strip: 27
            case .tab: 54
            }
        }
    }

    let request: PermissionRequest
    let others: Int
    /// Says whether the card on screen takes answers yet.
    let queue: PermissionQueue
    var placement: Placement = .strip
    let decide: (String, PermissionAnswer) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            card(isArmed: queue.armedID == request.id)
                .id(request.id)
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)), removal: .opacity))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: request.id)
    }

    private func card(isArmed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: request.source.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange)
                Text(PermissionCardText.toolName(of: request))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NotchTokens.primaryText)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(PermissionCardText.title(of: request))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchTokens.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let queued = PermissionCardText.queued(others) {
                    Text(queued)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NotchTokens.secondaryText)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(PermissionCardText.scrolled(of: request))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(NotchTokens.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .scrollIndicators(.visible)
            .frame(height: placement.textHeight)
            HStack(spacing: 6) {
                ForEach(PermissionCardText.buttons(for: request), id: \.answer) { button in
                    Button(button.label) { decide(request.id, button.answer) }
                        .buttonStyle(PermissionButtonStyle(tint: Self.tint(of: button.answer)))
                        // The short answers keep their width; the long one gives way first.
                        .layoutPriority(button.answer == .ask ? 0 : 1)
                }
                if let notice = PermissionCardText.notice(of: request) {
                    Text(notice)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.orange)
                        .lineLimit(1)
                        .layoutPriority(0)
                }
            }
            // Dimmed and out of reach while the card waits out its delay.
            .opacity(isArmed ? 1 : 0.4)
            .disabled(!isArmed)
            .animation(.easeOut(duration: 0.15), value: isArmed)
        }
        .padding(.vertical, 3)
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
