import NotchUI
import SwiftUI

/// One session: agent, project and branch, the tool it runs now, its state and how long the turn has run or took.
/// Clicking opens the project folder in Terminal; the context menu opens it in Finder or copies its path.
struct AgentSessionRow: View {
    let row: AgentTabState.Row
    let actions: AgentTabActions

    @Environment(\.notch) private var notch
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: row.source.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTokens.secondaryText)
                .frame(width: 16)
            Text(row.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(1)
                // Keeps its width first, so a long tool summary is cut before the project name.
                .layoutPriority(1)
            if let detail = row.detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTokens.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            StatusChip(status: row.status)
            Elapsed(timing: row.timing)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(isHovering ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onTapGesture(perform: open)
        .contextMenu {
            Button("Mở thư mục", systemImage: "folder") { actions.openFolder(row.cwd) }
                .disabled(row.cwd == nil)
            Button("Copy đường dẫn", systemImage: "doc.on.doc") { actions.copyPath(row.cwd) }
                .disabled(row.cwd == nil)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Mở thư mục dự án trong Terminal")
        .accessibilityAction(.default, open)
    }

    private func open() {
        if actions.openInTerminal(row.cwd) { notch.close() }
    }
}

private struct StatusChip: View {
    let status: AgentTabState.Status

    private var tint: Color {
        switch status {
        case .working: NotchTokens.accent
        case .waitingForInput: .orange
        case .finished: .green
        case .idle: NotchTokens.secondaryText
        case .error: .red
        }
    }

    var body: some View {
        Text(status.label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.18)))
    }
}

/// The turn's time: counting live while it runs, fixed once it ended.
private struct Elapsed: View {
    let timing: AgentTabState.Timing

    var body: some View {
        Group {
            switch timing {
            case let .running(since):
                Text(timerInterval: since...Date.distantFuture, countsDown: false)
            case let .took(seconds):
                Text(AgentFormat.duration(seconds))
            case .unknown:
                Text(" ")
            }
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundStyle(NotchTokens.secondaryText)
        .lineLimit(1)
    }
}
