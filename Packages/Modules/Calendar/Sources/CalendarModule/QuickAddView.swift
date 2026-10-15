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
                .background(Color.white.opacity(isHovering ? 0.16 : 0.08), in: Circle())
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

    static let prompt = "Thêm sự kiện: “họp nhóm 3h chiều mai”"
    static let examples = "Ví dụ: “gym 18h-19h”, “ăn trưa với Lan 12:30 thứ 6”, “call Sam tomorrow 9am 30m”."
    static let noTitle = "(Chưa có tiêu đề)"
    static let defaultCalendarName = "Lịch mặc định của hệ thống"
    static let saveFailed = "Không lưu được sự kiện. Nhấn Return để thử lại."
    /// The permission hint the module already shows in Settings, with the step that grants it.
    static let noAccess = "Cần quyền truy cập Lịch đầy đủ để thêm sự kiện. \(Permission.calendars.instruction)"

    /// The line at the bottom: the keys, or the state of the save.
    static func hint(for phase: QuickAddState.Phase) -> String {
        switch phase {
        case .editing: "Return để lưu · Esc để hủy"
        case .saving: "Đang lưu…"
        case .failed: saveFailed
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if quickAdd.canWrite {
                field
                preview
                Spacer(minLength: 0)
                Text(Self.hint(for: quickAdd.phase))
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
        // The notch is always black, whatever the system appearance.
        .environment(\.colorScheme, .dark)
        // Typing in the field must not be cut off by the pointer leaving the notch.
        .onAppear { notch.setPinned(true) }
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
            .tint(NotchTokens.accent)
            .focused($isFocused)
            .onSubmit(actions.saveQuickAdd)
            .onExitCommand(perform: actions.cancelQuickAdd)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .onAppear { isFocused = true }
            // The notch panel turns key only after the click that opened the field, so the first request can come too early.
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in isFocused = true }
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
                    .foregroundStyle(NotchTokens.accent)
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
