import AppKit
import MyNotchCore
import NotchUI
import SwiftUI

/// The "+" of the tab's header: opens the quick-add field, and closes it again while it is open.
struct AddEventButton: View {
    let isOpen: Bool
    let actions: CalendarActions
    @State private var isHovering = false

    static func help(isOpen: Bool) -> String { isOpen ? "Đóng (Esc)" : "Thêm sự kiện" }

    var body: some View {
        Button(action: isOpen ? actions.cancelQuickAdd : actions.openQuickAdd) {
            Image(systemName: isOpen ? "xmark" : "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isHovering ? NotchTokens.primaryText : NotchTokens.secondaryText)
                .frame(width: CalendarTabView.headerHeight, height: CalendarTabView.headerHeight)
                .background(NotchTokens.fill(isHovering ? 0.16 : 0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(Self.help(isOpen: isOpen))
        .accessibilityLabel(isOpen ? "Đóng ô thêm sự kiện" : "Thêm sự kiện")
    }
}

/// What the tab shows in place of the card and the list while the quick-add field is open: one line to type, what it
/// was read as, and the keys. Return saves, Esc drops it. Without full Calendar access there is a hint instead.
struct QuickAddView: View {
    let quickAdd: QuickAddState
    let now: Date
    let calendar: Calendar
    let actions: CalendarActions

    @FocusState private var isFocused: Bool
    @Environment(\.notch) private var notch
    @Environment(\.notchAccent) private var accent
    /// The notch's panel and whether it has the keyboard now. It can be shown without it (opened by hovering).
    @State private var window: NSWindow?
    @State private var panelIsKey = false

    static let prompt = "Thêm sự kiện: “họp nhóm 3h chiều mai”"
    static let examples = "Ví dụ: “gym 18h-19h”, “ăn trưa với Lan 12:30 thứ 6”, “call Sam tomorrow 9am 30m”."
    static let noTitle = "(Chưa có tiêu đề)"
    static let defaultCalendarName = "Lịch mặc định của hệ thống"
    static let saveFailed = "Không lưu được sự kiện. Nhấn Return để thử lại."
    /// The permission hint the module already shows in Settings, with the step that grants it.
    static let noAccess = "Cần quyền truy cập Lịch đầy đủ để thêm sự kiện. \(Permission.calendars.instruction)"

    /// The line at the bottom: the keys, or the state of the save. Opened by hovering, the notch can show the field with the
    /// keyboard still in another app; Esc would go there, so the field says it wants a click first.
    static func hint(for phase: QuickAddState.Phase, isTyping: Bool) -> String {
        switch phase {
        case .editing: isTyping ? "Return để lưu · Esc để hủy" : "Bấm vào ô để gõ"
        case .saving: "Đang lưu…"
        case .failed: saveFailed
        }
    }

    /// Whether the notch stays open while the pointer is elsewhere: only for a line that has been typed and whose panel
    /// still has the keyboard. An empty field, the permission hint, or a panel the user left for another app must not
    /// hold the notch open.
    static func pinsNotch(_ quickAdd: QuickAddState, panelIsKey: Bool) -> Bool {
        quickAdd.canWrite && !quickAdd.text.isEmpty && panelIsKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if quickAdd.canWrite {
                field
                preview
                Spacer(minLength: 0)
                Text(Self.hint(for: quickAdd.phase, isTyping: isFocused && panelIsKey))
                    .font(.system(size: 10))
                    .foregroundStyle(quickAdd.phase == .failed ? Color.red : NotchTokens.secondaryText)
                    .lineLimit(1)
            } else {
                Text(Self.noAccess)
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTokens.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The classic notch is black whatever the system appearance; on Liquid Glass the field follows the glass.
        .notchColorScheme()
        .background(WindowReader { window in
            self.window = window
            panelIsKey = window?.isKeyWindow ?? false
        })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard let window, note.object as? NSWindow === window else { return }
            panelIsKey = true
            isFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            guard let window, note.object as? NSWindow === window else { return }
            panelIsKey = false
        }
        // A line being typed must not be cut off by the pointer leaving the notch; nothing else holds it open.
        .onChange(of: Self.pinsNotch(quickAdd, panelIsKey: panelIsKey), initial: true) { _, pins in notch.setPinned(pins) }
        .onDisappear { notch.setPinned(false) }
    }

    private var text: Binding<String> {
        Binding(get: { quickAdd.text }, set: { actions.editQuickAdd($0) })
    }

    private var field: some View {
        TextField("Thêm sự kiện", text: text, prompt: Text(Self.prompt).foregroundStyle(NotchTokens.secondaryText))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(NotchTokens.primaryText)
            .tint(accent)
            .focused($isFocused)
            .onSubmit(actions.saveQuickAdd)
            .onExitCommand(perform: actions.cancelQuickAdd)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            // A click on the padding goes to the field too. Behind the field, so it never takes a click from the text.
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(NotchTokens.fill(0.1))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { isFocused = true }
            }
            // Asked again a turn later: SwiftUI drops a request made in the pass that creates the field.
            .onAppear {
                isFocused = true
                Task { @MainActor in isFocused = true }
            }
    }

    @ViewBuilder
    private var preview: some View {
        if let draft = quickAdd.draft {
            VStack(alignment: .leading, spacing: 3) {
                Text(draft.title.isEmpty ? Self.noTitle : draft.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(draft.title.isEmpty ? NotchTokens.secondaryText : NotchTokens.primaryText)
                    .lineLimit(1)
                Text(AgendaFormat.when(of: draft, now: now, calendar: calendar))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(accent)
                    .lineLimit(1)
                calendarLine
                if let note = draft.note {
                    Label(AgendaFormat.text(of: note), systemImage: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.orange)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 2)
        } else {
            Text(Self.examples)
                .font(.system(size: 11))
                .foregroundStyle(NotchTokens.secondaryText)
                .lineLimit(2)
                .padding(.horizontal, 2)
        }
    }

    /// "● Work": the calendar's colour dot and name, as the card shows them.
    private var calendarLine: some View {
        HStack(spacing: 4) {
            Circle().fill(quickAdd.calendar.map { Color($0.color) } ?? Color.gray).frame(width: 6, height: 6)
            Text(quickAdd.calendar?.title ?? Self.defaultCalendarName)
                .font(.system(size: 11))
                .foregroundStyle(NotchTokens.secondaryText)
                .lineLimit(1)
        }
    }
}

/// Hands over the window a view is in, once it has one, and again if it moves to another.
private struct WindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = Reader()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    final class Reader: NSView {
        var onChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let window = window
            // After the view update that added it, so state may be set from the callback.
            DispatchQueue.main.async { [weak self] in self?.onChange?(window) }
        }
    }
}
