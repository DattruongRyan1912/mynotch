import SwiftUI
import NotchUI

/// Giao diện tab hiển thị bên trong Notch macOS (Chiều cao chuẩn 220pt) theo chuẩn Linear / Developer Ergonomics.
public struct HabitTabView: View {
    public static let height: CGFloat = 220
    public static let headerHeight: CGFloat = 18

    @Bindable public var state: HabitState
    public var onSave: (() -> Void)?
    public var onAppear: (() -> Void)?

    @Environment(\.notch) private var notch
    @Environment(\.notchAccent) private var accent

    @State private var newHabitTitle: String = ""
    @FocusState private var isInputFocused: Bool

    public init(state: HabitState, onSave: (() -> Void)? = nil, onAppear: (() -> Void)? = nil) {
        self.state = state
        self.onSave = onSave
        self.onAppear = onAppear
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            quickAddField
            habitList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .notchColorScheme()
        .onAppear { onAppear?() }
        .onChange(of: !newHabitTitle.isEmpty && isInputFocused, initial: true) { _, pins in
            notch.setPinned(pins)
        }
        .onDisappear {
            notch.setPinned(false)
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTokens.secondaryText)

            Text("Thói quen")
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(state.progress.formattedText)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(NotchTokens.secondaryText)
                .lineLimit(1)
        }
        .frame(height: Self.headerHeight)
    }

    // MARK: - Quick Add Field
    private var quickAddField: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NotchTokens.secondaryText)

            TextField("Thêm thói quen…", text: $newHabitTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(NotchTokens.primaryText)
                .focused($isInputFocused)
                .onSubmit {
                    submitNewHabit()
                }
                .onExitCommand {
                    if newHabitTitle.isEmpty {
                        notch.close()
                    } else {
                        newHabitTitle = ""
                    }
                }

            if !newHabitTitle.isEmpty {
                Button {
                    newHabitTitle = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTokens.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(NotchTokens.fill(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isInputFocused ? accent.opacity(0.6) : Color.clear, lineWidth: 1)
        )
    }

    private func submitNewHabit() {
        if state.addHabit(title: newHabitTitle) != nil {
            newHabitTitle = ""
            onSave?()
        }
    }

    // MARK: - Habit List
    private var habitList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                if state.habits.isEmpty {
                    Text("Chưa có thói quen nào.")
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTokens.secondaryText)
                        .padding(.top, 16)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(state.habits) { habit in
                        HabitRowView(
                            habit: habit,
                            today: state.today,
                            calendar: state.calendar,
                            onToggleToday: {
                                state.toggleToday(id: habit.id)
                                onSave?()
                            },
                            onToggleDay: { day in
                                state.toggle(id: habit.id, on: day)
                                onSave?()
                            },
                            onDelete: {
                                state.deleteHabit(id: habit.id)
                                onSave?()
                            }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Single Habit Row
private struct HabitRowView: View {
    let habit: Habit
    let today: DayKey
    let calendar: Calendar
    let onToggleToday: () -> Void
    let onToggleDay: (DayKey) -> Void
    let onDelete: () -> Void

    @Environment(\.notchAccent) private var accent
    @State private var isHovered: Bool = false

    private var isDoneToday: Bool {
        habit.isCompleted(on: today)
    }

    private var currentStreak: Int {
        habit.streak(on: today, calendar: calendar)
    }

    private var lastSeven: [Bool] {
        habit.lastSevenDays(endingOn: today, calendar: calendar)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox
            Button(action: onToggleToday) {
                Image(systemName: isDoneToday ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14.5))
                    .foregroundStyle(isDoneToday ? accent : NotchTokens.secondaryText)
            }
            .buttonStyle(.plain)

            // Habit title (pure typography, zero emoji)
            Text(habit.title)
                .font(.system(size: 12))
                .foregroundStyle(isDoneToday ? NotchTokens.secondaryText : NotchTokens.primaryText)
                .strikethrough(isDoneToday, color: NotchTokens.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Mini 7-day Heatmap (GitHub contribution style)
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { index in
                    let isDone = lastSeven[index]
                    let dayOffset = index - 6
                    let dayKey = today.addingDays(dayOffset, calendar: calendar)

                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(isDone ? accent.opacity(0.85) : NotchTokens.fill(0.12))
                        .frame(width: 7, height: 7)
                        .overlay(
                            index == 6 ?
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .stroke(NotchTokens.fill(0.45), lineWidth: 0.8)
                            : nil
                        )
                        .onTapGesture {
                            onToggleDay(dayKey)
                        }
                        .help(index == 6 ? "Hôm nay: \(isDone ? "Đã làm" : "Chưa làm")" : "\(dayKey.description): \(isDone ? "Đã làm" : "Chưa làm")")
                }
            }

            // Streak pill (Clean monospace tabular)
            Text("\(currentStreak)d")
                .font(.system(size: 11, weight: currentStreak > 0 ? .medium : .regular).monospacedDigit())
                .foregroundStyle(currentStreak > 0 ? NotchTokens.primaryText : NotchTokens.secondaryText.opacity(0.5))
                .frame(minWidth: 28, alignment: .trailing)

            // Subtle hover delete
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            } else {
                Color.clear
                    .frame(width: 10, height: 10)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHovered ? NotchTokens.fill(0.06) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Xoá thói quen", systemImage: "trash")
            }
        }
    }
}
