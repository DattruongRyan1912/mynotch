import AppKit
import NotchUI
import SwiftUI

/// The "Cổng" tab: two fields (filter, and "Cổng nào đang bị chiếm?"), one row per port, and a footnote.
struct PortsTabView: View {
    static let footnote = "Cổng của hệ thống cần quyền quản trị"
    static let filterPrompt = "Lọc theo cổng hoặc tên"
    static let quickPrompt = "Cổng nào đang bị chiếm?"

    enum Field: Hashable { case filter, quick }

    @Bindable var state: PortsState
    let actions: PortsActions

    @FocusState private var focused: Field?
    @Environment(\.notch) private var notch

    /// Whether the notch stays open while the pointer is elsewhere: while something is being typed or a stop waits for an answer.
    static func pinsNotch(typing: Bool, needsAnswer: Bool) -> Bool { typing || needsAnswer }

    var body: some View {
        let pins = Self.pinsNotch(typing: focused != nil && !(state.filter.isEmpty && state.quickQuery.isEmpty), needsAnswer: state.needsAnswer)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PortsField(icon: "line.3.horizontal.decrease", prompt: Self.filterPrompt, text: $state.filter, field: .filter, focused: $focused)
                PortsField(icon: "questionmark.circle", prompt: Self.quickPrompt, text: $state.quickQuery, field: .quick, focused: $focused)
            }
            if let answer = state.quickAnswer.message {
                QuickAnswerLine(answer: state.quickAnswer, message: answer)
            }
            PortsList(state: state, actions: actions)
            Text(state.notice ?? Self.footnote)
                .font(.system(size: 10))
                .foregroundStyle(state.notice == nil ? NotchTokens.secondaryText : NotchTokens.primaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The classic notch is black whatever the system appearance; on Liquid Glass the tab follows the glass.
        .notchColorScheme()
        .onAppear(perform: actions.appeared)
        .onDisappear {
            actions.disappeared()
            notch.setPinned(false)
        }
        .onChange(of: state.quickQuery) { actions.quickChanged() }
        .onChange(of: pins, initial: true) { _, pins in notch.setPinned(pins) }
    }
}

private struct PortsField: View {
    let icon: String
    let prompt: String
    @Binding var text: String
    let field: PortsTabView.Field
    var focused: FocusState<PortsTabView.Field?>.Binding

    @Environment(\.notch) private var notch
    @Environment(\.notchAccent) private var accent

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(NotchTokens.secondaryText)
            TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(NotchTokens.secondaryText))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(NotchTokens.primaryText)
                .tint(accent)
                .focused(focused, equals: field)
                // Esc clears a line; with nothing to clear it closes the notch, so a focused field is no trap.
                .onExitCommand { if text.isEmpty { notch.close() } else { text = "" } }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        // A click on the padding goes to the field too. Behind the field, so it never takes a click from the text.
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(NotchTokens.fill(0.1))
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture { focused.wrappedValue = field }
        }
    }
}

private struct QuickAnswerLine: View {
    let answer: PortQuickCheck.Answer
    let message: String

    private var tint: Color {
        switch answer {
        case .free: .green
        case .busyUnseen: .orange
        case .owner: NotchTokens.primaryText
        default: NotchTokens.secondaryText
        }
    }

    private var symbol: String {
        switch answer {
        case .free: "checkmark.circle"
        case .owner: "arrow.right.circle"
        case .busyUnseen: "exclamationmark.circle"
        default: "info.circle"
        }
    }

    var body: some View {
        Label(message, systemImage: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PortsList: View {
    let state: PortsState
    let actions: PortsActions

    var body: some View {
        let rows = state.visibleEntries
        if !state.hasLoaded {
            Spacer(minLength: 0)
        } else if rows.isEmpty {
            Label(state.filter.isEmpty ? "Không có cổng nào đang mở" : "Không có cổng nào khớp", systemImage: "network.slash")
                .font(.system(size: 12))
                .foregroundStyle(NotchTokens.secondaryText)
                .padding(.vertical, 4)
            Spacer(minLength: 0)
        } else {
            ScrollView {
                PortsRows(entries: rows, flows: state.flows, showsCommandLines: state.showsCommandLines, actions: actions)
            }
            .scrollIndicators(.never)
        }
    }
}

/// The rows themselves, without the scrolling around them.
struct PortsRows: View {
    let entries: [PortEntry]
    let flows: [Int32: StopFlow]
    let showsCommandLines: Bool
    let actions: PortsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(entries) { entry in
                PortRow(
                    entry: entry, flow: flows[entry.pid].flatMap { $0.entry.id == entry.id ? $0 : nil },
                    showsCommandLine: showsCommandLines, actions: actions,
                    // One stop at a time per process: while one is asked or running, its other rows have no button.
                    canStop: actions.canStop(entry) && flows[entry.pid] == nil
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One port: its number, a hint for the well-known ones, who holds it and how, and what can be done with it. While a stop is being
/// asked, the row says that instead.
struct PortRow: View {
    let entry: PortEntry
    let flow: StopFlow?
    let showsCommandLine: Bool
    let actions: PortsActions
    let canStop: Bool

    @State private var isHovering = false

    /// The line under the name: what the process was started with, or nothing while MyNotch is kept out of recordings.
    static func commandLine(of entry: PortEntry, shown: Bool) -> String? { shown ? entry.process.commandLine : nil }

    var body: some View {
        Group {
            if let flow { PortFlowRow(flow: flow, actions: actions) } else { details }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(NotchTokens.fill(isHovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6))
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
    }

    private var details: some View {
        HStack(spacing: 8) {
            PortIcon(path: entry.process.appBundlePath)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(String(entry.port))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(NotchTokens.primaryText)
                    if entry.proto == .udp { PortBadge(text: "UDP") }
                    if let label = DevPortLabel.label(for: entry.port) { PortBadge(text: label) }
                    Text(entry.process.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(NotchTokens.primaryText)
                        .lineLimit(1)
                        .help(entry.process.fullName)
                    Text("PID \(entry.pid)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(NotchTokens.secondaryText)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Reach(entry: entry)
                    if let command = Self.commandLine(of: entry, shown: showsCommandLine) {
                        Text(command)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(NotchTokens.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                if entry.proto == .tcp { PortChip(title: "Mở", label: "Mở cổng \(entry.port) trong trình duyệt") { actions.open(entry) } }
                PortChip(title: "Chép", label: "Chép localhost:\(entry.port)") { actions.copy(entry) }
                if canStop {
                    PortChip(title: "Dừng", tint: .red, label: "Dừng \(entry.process.fullName), cổng \(entry.port)") { actions.requestStop(entry) }
                }
            }
        }
    }
}

/// "Chỉ máy này" for 127.0.0.1 and ::1, "Cả mạng" for what other machines can reach.
private struct Reach: View {
    let entry: PortEntry

    var body: some View {
        Label(entry.isLocalOnly ? "Chỉ máy này" : "Cả mạng", systemImage: entry.isLocalOnly ? "lock.fill" : "network")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(entry.isLocalOnly ? NotchTokens.secondaryText : Color.orange)
            .lineLimit(1)
            .fixedSize()
            .help(entry.addressText)
    }
}

/// The question, or the offer, that replaces a row while a stop is in progress, and its buttons.
private struct PortFlowRow: View {
    let flow: StopFlow
    let actions: PortsActions

    var body: some View {
        let pid = flow.entry.pid
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.orange)
            Text(flow.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            switch flow.phase {
            case .confirming:
                PortChip(title: "Dừng", tint: .red, label: "Xác nhận dừng") { actions.confirmStop(pid) }
                PortChip(title: "Huỷ", label: "Huỷ") { actions.cancelStop(pid) }
            case .stillRunning:
                PortChip(title: "Buộc dừng", tint: .red, label: "Buộc dừng") { actions.forceStop(pid) }
                PortChip(title: "Để yên", label: "Để yên") { actions.cancelStop(pid) }
            case .refused, .failed:
                PortChip(title: "Đóng", label: "Đóng") { actions.cancelStop(pid) }
            case .stopping, .forcing:
                EmptyView()
            }
        }
        .frame(minHeight: 30)
    }
}

private struct PortChip: View {
    let title: String
    var tint: Color?
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint ?? NotchTokens.primaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tint?.opacity(0.18) ?? NotchTokens.fill(0.14), in: Capsule())
                .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct PortBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(NotchTokens.secondaryText)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(NotchTokens.fill(0.1), in: Capsule())
            .lineLimit(1)
            .fixedSize()
    }
}

/// The app's icon when the process belongs to an app, a terminal otherwise.
private struct PortIcon: View {
    let path: String?

    var body: some View {
        Group {
            if let path {
                Image(nsImage: PortIconCache.icon(forAppAt: path))
                    .resizable()
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 13))
                    .foregroundStyle(NotchTokens.secondaryText)
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

/// Icons by app path: asking the workspace for one is slow enough that a list redrawn every two seconds must not.
enum PortIconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(forAppAt path: String) -> NSImage {
        if let icon = icons[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 20, height: 20)
        icons[path] = icon
        return icon
    }
}
