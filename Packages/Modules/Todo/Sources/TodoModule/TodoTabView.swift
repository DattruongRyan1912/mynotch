import AppKit
import MyNotchCore
import NotchUI
import SwiftUI

/// The "Việc cần làm" tab: the quick-add field, the count of what is done, and today's list.
struct TodoTabView: View {
    /// The notch's preferred height for the tab: the area below the notch, tab bar and inner padding included.
    static let height: CGFloat = 220
    /// The header line: "Hôm nay" and the count.
    static let headerHeight: CGFloat = 18

    let state: TodoState
    let actions: TodoActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            switch state.phase {
            case .needsAccess:
                AccessHint(isDenied: state.accessIsDenied, actions: actions)
            case .loading, .ready:
                TodoQuickAddField(state: state, actions: actions)
                if let notice = state.notice {
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTokens.secondaryText)
                        .lineLimit(1)
                }
                if state.loadFailed { LoadFailedLine(actions: actions) }
                TodoList(state: state, actions: actions)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The classic notch is black whatever the system appearance; on Liquid Glass the tab follows the glass.
        .notchColorScheme()
        .onAppear(perform: actions.appeared)
        // While the hint shows, the tab watches for access: a grant elsewhere re-mounts nothing. Cancelled when it goes.
        .task(id: state.phase) {
            if state.phase == .needsAccess { await actions.watchAccess() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Hôm nay")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
            if state.phase == .ready {
                Text(TodoFormat.progress(state.progress))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(NotchTokens.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(height: Self.headerHeight)
    }
}

/// Without Reminders access: what is missing and the one button that asks. After a refusal only System Settings can change
/// the answer, so the button says that is where it goes.
private struct AccessHint: View {
    let isDenied: Bool
    let actions: TodoActions

    static let notAsked = "Cần quyền truy cập Lời nhắc để hiện và thêm việc cần làm."
    static let denied = "\(notAsked) \(Permission.reminders.instruction)"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isDenied ? Self.denied : Self.notAsked)
                .font(.system(size: 12))
                .foregroundStyle(NotchTokens.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: actions.requestAccess) {
                Label(isDenied ? "Mở Cài đặt hệ thống" : "Cho phép truy cập Lời nhắc", systemImage: isDenied ? "gearshape" : "checklist")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTokens.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(NotchTokens.fill(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Reminders answered with nothing, which is not the same as having nothing to do: the list below, if any, is what was read
/// before, and the button reads again.
private struct LoadFailedLine: View {
    let actions: TodoActions

    var body: some View {
        HStack(spacing: 8) {
            Label("Không đọc được Lời nhắc.", systemImage: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(Color.orange)
                .lineLimit(1)
            Button(action: actions.retry) {
                Text("Thử lại")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTokens.primaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(NotchTokens.fill(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

/// "Thêm việc…": Return saves what the line says, Esc clears it. The line is read as it is typed, and what was read
/// (a day, a time, a priority) is named at its right edge, so a surprise shows before Return.
struct TodoQuickAddField: View {
    let state: TodoState
    let actions: TodoActions

    @State private var text = ""
    @State private var isSaving = false
    /// Set by the quick-add shortcut and held for a moment: the panel may only become the key window after the field was
    /// asked for focus, and SwiftUI drops a request made in the pass that creates the field.
    @State private var wantsFocus = false
    @FocusState private var isFocused: Bool
    @Environment(\.notch) private var notch
    @Environment(\.notchAccent) private var accent

    static let prompt = "Thêm việc…"

    /// Whether the notch stays open while the pointer is elsewhere: only for a line that is being typed. An empty field must
    /// not hold the notch open.
    static func pinsNotch(text: String, isFocused: Bool) -> Bool {
        !text.isEmpty && isFocused
    }

    private var hint: String? {
        TodoQuickAddParser.parse(text, now: state.now, calendar: state.calendar)
            .flatMap { TodoFormat.hint(for: $0, now: state.now, calendar: state.calendar) }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(NotchTokens.secondaryText)
            TextField(Self.prompt, text: $text, prompt: Text(Self.prompt).foregroundStyle(NotchTokens.secondaryText))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(NotchTokens.primaryText)
                .tint(accent)
                .focused($isFocused)
                .onSubmit(submit)
                // Esc clears a line; with nothing to clear it closes the notch, so the shortcut's focused field is no trap.
                .onExitCommand { if text.isEmpty { notch.close() } else { text = "" } }
            if let hint {
                Text(hint)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(accent)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // A click on the padding goes to the field too. Behind the field, so it never takes a click from the text.
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(NotchTokens.fill(0.1))
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture { isFocused = true }
        }
        // Only the quick-add shortcut asks for focus, and the request is served once: the field mounts again whenever the notch
        // opens, and that must not take the keyboard.
        .onAppear { if state.takeFocusRequest() { requestFocus() } }
        .onChange(of: state.pendingFocus) { if state.takeFocusRequest() { requestFocus() } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            if wantsFocus { isFocused = true }
        }
        // A line being typed must not be cut off by the pointer leaving the notch; nothing else holds it open.
        .onChange(of: Self.pinsNotch(text: text, isFocused: isFocused), initial: true) { _, pins in notch.setPinned(pins) }
        .onDisappear { notch.setPinned(false) }
    }

    private func requestFocus() {
        wantsFocus = true
        isFocused = true
        Task { @MainActor in
            isFocused = true
            try? await Task.sleep(for: .seconds(2))
            wantsFocus = false
        }
    }

    private func submit() {
        guard !isSaving, !text.isEmpty else { return }
        isSaving = true
        let line = text
        Task { @MainActor in
            if await actions.add(line), text == line { text = "" }
            isSaving = false
        }
    }
}

/// Today's rows, or what to say when there are none.
private struct TodoList: View {
    let state: TodoState
    let actions: TodoActions

    var body: some View {
        let rows = state.rows
        if state.phase == .loading {
            Spacer(minLength: 0)
        } else if rows.isEmpty {
            // A list that could not be read is not an empty one, and the line above already says so.
            if !state.loadFailed {
                Label(state.items.isEmpty ? "Hôm nay chưa có việc nào" : "Đã xong hết việc hôm nay", systemImage: "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTokens.secondaryText)
                    .padding(.vertical, 4)
            }
            Spacer(minLength: 0)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(rows) { item in
                        TodoRow(
                            item: item, isLingering: state.lingering.contains(item.id), now: state.now, calendar: state.calendar,
                            complete: { actions.complete(item.id) }, undo: { actions.undo(item.id) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
    }
}
