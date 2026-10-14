import AppKit
import NotchUI
import SwiftUI

/// The "AI" tab: the permission request waiting for an answer, then one row per session, newest activity first, and
/// today's usage and Codex's limits below.
struct AIAgentsTabView: View {
    let store: AgentSessionStore
    let permissions: PermissionQueue
    let actions: AgentTabActions

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
                    PermissionCard(request: request, others: permissions.pending.count - 1, decide: actions.decide)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
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

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 22))
            Text(AgentTabState.emptyMessage)
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(NotchTokens.secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
