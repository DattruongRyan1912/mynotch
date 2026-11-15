import AppKit
import NotchUI
import SwiftUI

/// The "AI" tab: the permission request waiting for an answer, then one row per session, newest activity first, and
/// today's usage and Codex's limits below.
struct AIAgentsTabView: View {
    let store: AgentSessionStore
    let permissions: PermissionQueue
    let actions: AgentTabActions
    var hint = AgentJumpHint()

    @Environment(\.notch) private var notch
    /// A menu of this app is being tracked, e.g. a row's context menu.
    @State private var isMenuOpen = false

    var body: some View {
        // Drawn again every half minute. Nothing in the store changes when a rate-limit window resets or the day
        // rolls over at midnight (today's usage then starts from zero), so the clock has to prompt it.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let state = AgentTabState(store: store, now: .now)
            VStack(alignment: .leading, spacing: 6) {
                if let request = permissions.pending.first {
                    PermissionCard(request: request, others: permissions.pending.count - 1, queue: permissions, placement: .tab, decide: actions.decide)
                        .padding(.horizontal, PermissionCard.tabInset)
                        .background(RoundedRectangle(cornerRadius: 8).fill(NotchTokens.fill(0.08)))
                }
                if let message = hint.message {
                    HintBanner(message: message, dismiss: hint.dismiss)
                }
                if state.isEmpty {
                    EmptyState()
                } else {
                    list(state.rows)
                }
                if !state.usage.isEmpty || !state.limits.isEmpty {
                    AgentUsageFooter(usage: state.usage, limits: state.limits)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // The context menu lives outside the notch's reach: a click there counts as outside and the pointer may
        // leave the notch, so the notch stays pinned while a menu is open.
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            isMenuOpen = true
            notch.setPinned(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            isMenuOpen = false
            notch.setPinned(false)
        }
        .onDisappear {
            if isMenuOpen { notch.setPinned(false) }
        }
    }

    private func list(_ rows: [AgentTabState.Row]) -> some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(rows) { row in
                    AgentSessionRow(row: row, actions: actions)
                }
            }
        }
        .scrollIndicators(.never)
    }
}

/// What a click could not do and the user can fix, with a button that makes it go away.
private struct HintBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(NotchTokens.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Đã hiểu", action: dismiss)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NotchTokens.primaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(NotchTokens.fill(0.08)))
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 22))
            Text(AgentTabState.emptyMessage)
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(NotchTokens.secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
