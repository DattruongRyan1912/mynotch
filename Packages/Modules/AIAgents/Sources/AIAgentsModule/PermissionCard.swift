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
    /// A tool name longer than this is also written as the first line of the text, since the row it sits on cannot show more.
    static let longToolName = 22

    /// What a card can do with a request at all: offer to allow it, or only to deny it and leave the rest to the terminal.
    nonisolated enum Eligibility: Equatable, Sendable {
        /// Whole and plain text: "Cho phép" is offered when the layout puts all of the text on the card.
        case offerable
        /// Something was cut, or the helper did not know the tool.
        case notWhole
        /// A character that is not printable ASCII: the card cannot promise to show it as it is.
        case notPlain
        /// The folder in the title has a character that could not be drawn as what it is.
        case folderUnreadable
    }

    static func eligibility(of request: PermissionRequest) -> Eligibility {
        guard request.isWhole else { return .notWhole }
        guard request.isPlain else { return .notPlain }
        return request.folderIsReadable ? .offerable : .folderUnreadable
    }

    /// "Cho phép" only for a whole, plain request whose whole text is on this card; `fits` is the layout's to say. A request
    /// that is plain and whole but too much for the strip can only be denied there, and is read in the AI tab; one too much
    /// for the tab, or not whole or not plain, is answered where all of it is shown as it is, in the terminal, and the
    /// notch can only deny.
    static func buttons(for request: PermissionRequest, fits: Bool, in placement: PermissionPlacement) -> [Button] {
        switch eligibility(of: request) {
        case .offerable where fits: [Button("Cho phép", .allow), Button("Từ chối", .deny), Button("Hỏi trong terminal", .ask)]
        case .offerable where placement == .strip: [Button("Từ chối", .deny)]
        case .offerable, .notWhole, .notPlain, .folderUnreadable: [Button("Từ chối", .deny), Button("Trả lời trong terminal", .ask)]
        }
    }

    /// The agent and, when the request knows it, the folder it works in, cleaned: accents and other scripts as they are, and a
    /// character that cannot be drawn as what it is replaced by U+FFFD (which also stops the request being allowed).
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

    /// Said beside the buttons of a request that cannot be allowed on this card.
    static func notice(of request: PermissionRequest, fits: Bool, in placement: PermissionPlacement) -> String? {
        switch eligibility(of: request) {
        case .offerable where fits: nil
        case .offerable: placement == .strip ? "Mở tab AI để xem đủ" : "Quá dài để cho phép tại đây"
        case .notWhole: "Chưa đủ chi tiết để cho phép tại đây"
        case .notPlain: "Có ký tự ngoài ASCII: trả lời trong terminal"
        case .folderUnreadable: "Tên thư mục có ký tự lạ: trả lời trong terminal"
        }
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

/// Where a permission card is drawn.
nonisolated enum PermissionPlacement: Equatable, Sendable {
    /// Under the closed notch.
    case strip
    /// At the top of the AI tab.
    case tab

    /// How many lines of a text that does not fit are shown, ending in an ellipsis. It only sets what the preview looks
    /// like: whether "Cho phép" is offered is the layout's to say.
    var previewLines: Int {
        switch self {
        case .strip: 2
        case .tab: 6
        }
    }
}

/// The request an agent waits on, with its answers. The same card sits in the strip under the closed notch and at the top
/// of the AI tab.
///
/// "Cho phép" is on the card only when all of the request's text is on it, and the card knows that from the layout it is
/// drawn in: of two versions, the first has all of the text and the button, the second a preview with an ellipsis and no
/// button, and `ViewThatFits` takes the first whose height is no more than the room the card is given, at the width it is
/// given. Nothing about the width, the padding or the font is written down for this, so a change to the notch's padding or
/// size cannot make it wrong. A request that is not whole or not plain text gets only the second.
///
/// `ViewThatFits` judges the height only. It cannot judge the width too: with both axes it compares the ideal size of each
/// version, which for text is one unwrapped line, and then no command of more than a few characters fits the strip. The
/// width is kept by making nothing in the card rigid: the texts wrap or truncate and the buttons give way, so a version is
/// never wider than the room, whatever the tool name or the folder is (`PermissionCardLayoutTests` draws tool names of 4 to
/// 100 characters at every width and checks the card is where it is for a short one).
///
/// A card that has just come up, or that took the place of the one before it, takes no answer until its delay is over, and
/// changes visibly when it is replaced, so a click that began on the previous one does not land on this one.
struct PermissionCard: View {
    /// The strip under the closed notch: it can be at most `NotchGeometry.maxBottomHeight` (80) tall.
    static let stripHeight: CGFloat = 80
    /// The card's padding on each side in the AI tab.
    static let tabInset: CGFloat = 8
    /// The most the card takes of the AI tab, which has the session list under it. A text that does not fit this is not allowed.
    static let tabBudget: CGFloat = 140

    typealias Placement = PermissionPlacement

    let request: PermissionRequest
    let others: Int
    /// Says whether the card on screen takes answers yet.
    let queue: PermissionQueue
    var placement: Placement = .strip
    let decide: (String, PermissionAnswer) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .id(request.id)
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)), removal: .opacity))
        }
        .frame(maxWidth: .infinity, maxHeight: placement == .tab ? Self.tabBudget : nil, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.2), value: request.id)
    }

    @ViewBuilder private var content: some View {
        if PermissionCardText.eligibility(of: request) == .offerable {
            ViewThatFits(in: .vertical) {
                layout(fits: true)
                layout(fits: false)
            }
        } else {
            layout(fits: false)
        }
    }

    private func layout(fits: Bool) -> some View {
        PermissionCardLayout(request: request, others: others, queue: queue, placement: placement, fits: fits, decide: decide)
    }
}

/// One version of the card: `fits` says whether it has all of the text, and so the "Cho phép" button, or a preview of the
/// text and no such button.
struct PermissionCardLayout: View {
    let request: PermissionRequest
    let others: Int
    let queue: PermissionQueue
    let placement: PermissionPlacement
    let fits: Bool
    let decide: (String, PermissionAnswer) -> Void

    var body: some View {
        let isArmed = queue.armedID == request.id
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: request.source.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange)
                // Gives way to nothing but the title and the count, so a short name is whole, and a long one is cut with an
                // ellipsis without making the card wider than the notch: one of more than `longToolName` characters is the first
                // line of the text as well, where it wraps and is whole.
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
                    // The last to give way: the signal that more is waiting is worth more than the title or a long tool name.
                    Text(queued)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NotchTokens.secondaryText)
                        .lineLimit(1)
                        .layoutPriority(2)
                }
            }
            // All of it, in as many lines as it takes, or a preview that ends in an ellipsis.
            Text(PermissionCardText.scrolled(of: request))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(NotchTokens.secondaryText)
                .lineLimit(fits ? nil : placement.previewLines)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(PermissionCardText.buttons(for: request, fits: fits, in: placement), id: \.answer) { button in
                    Button(button.label) { decide(request.id, button.answer) }
                        .buttonStyle(PermissionButtonStyle(tint: Self.tint(of: button.answer)))
                        // The short answers keep their width; the long one gives way first.
                        .layoutPriority(button.answer == .ask ? 0 : 1)
                }
                if let notice = PermissionCardText.notice(of: request, fits: fits, in: placement) {
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
