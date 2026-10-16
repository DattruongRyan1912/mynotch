import MyNotchCore
import NotchUI
import SwiftUI

/// The "Hẹn giờ" tab: while idle a choice of type and the minute dial, otherwise the ring with the time left and its
/// controls, and once a timer ends the one-click next step.
struct TimerTabView: View {
    static let dialSize: CGFloat = 112
    static let pickerHeight: CGFloat = 22
    static let gap: CGFloat = 10
    /// The tab bar's height when there are two or more tabs; `NotchTab.preferredHeight` includes it.
    static let tabBarHeight: CGFloat = 30
    /// The picker and the dial, plus what the notch adds around a tab's content.
    static let preferredHeight = pickerHeight + gap + dialSize + NotchTokens.padding + tabBarHeight

    /// Counts down to `endDate` from a lower bound that never moves, so rebuilding the view cannot restart the text.
    static func countdownRange(to endDate: Date) -> ClosedRange<Date> { .distantPast...endDate }

    let state: TimerState
    let module: TimerModule

    @Environment(\.notch) private var notch
    @FocusState private var dialFocused: Bool

    var body: some View {
        VStack(spacing: Self.gap) {
            switch state.model {
            case .idle: idle
            case .finished: finished
            case .stopwatch, .stopwatchPaused: stopwatchActive
            case .countdown, .countdownPaused: countdownActive
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .defaultFocus($dialFocused, true)
        // The tab is in the tree only while it is shown (or under a toast), so this is the user opening it: a finish that rang
        // while it was closed has been seen.
        .onAppear { module.acknowledgeFinish() }
    }

    // MARK: Idle

    private var idle: some View {
        @Bindable var state = state
        return VStack(spacing: Self.gap) {
            Picker("Loại hẹn giờ", selection: $state.mode) {
                ForEach(TimerKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(TimerState.Mode.timer(kind))
                }
                Text("Bấm giờ").tag(TimerState.Mode.stopwatch)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 360, height: Self.pickerHeight)
            switch state.mode {
            case .timer(let kind): setter(kind)
            case .stopwatch: stopwatchStart
            }
        }
    }

    private func setter(_ kind: TimerKind) -> some View {
        @Bindable var state = state
        let minutes = module.minutes(for: kind)
        return HStack(spacing: 22) {
            MinuteSettingDial(kind: kind, minutes: minutes, size: Self.dialSize, focus: $dialFocused) {
                module.setMinutes($0, for: kind)
            }
            VStack(alignment: .leading, spacing: 10) {
                Label(kind.title, systemImage: kind.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(kind.accent)
                if kind == .reminder {
                    TextField("Nhắc việc gì?", text: $state.reminderLabel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .onSubmit { module.startFromTab(kind, minutes: minutes) }
                }
                // The quick lengths go when the open notch is too narrow for them.
                ViewThatFits(in: .horizontal) {
                    startRow(kind, minutes: minutes, showsQuickLengths: true)
                    startRow(kind, minutes: minutes, showsQuickLengths: false)
                }
            }
        }
        .frame(height: Self.dialSize)
    }

    private func startRow(_ kind: TimerKind, minutes: Int, showsQuickLengths: Bool) -> some View {
        HStack(spacing: 8) {
            Button("Bắt đầu") { module.startFromTab(kind, minutes: minutes) }
                .disabled(minutes == 0)
            if showsQuickLengths {
                ForEach(TimerLength.quick, id: \.minutes) { length in
                    Button(length.title) { module.startFromTab(kind, minutes: length.minutes) }
                        .controlSize(.small)
                }
            }
            Button("Dài hơn \(Image(systemName: "chevron.down"))") {
                TimerLengthMenu.show(TimerLength.longer, notch: notch) { module.startFromTab(kind, minutes: $0.minutes) }
            }
        }
        .fixedSize()
    }

    private var stopwatchStart: some View {
        VStack(spacing: 10) {
            Text("0:00")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchTokens.secondaryText)
            Button("Bắt đầu") { module.startStopwatch() }
        }
        .frame(height: Self.dialSize)
    }

    // MARK: Running

    private var countdownActive: some View {
        let session = state.session
        return HStack(spacing: 22) {
            RunningDial(model: state.model, session: session, size: Self.dialSize)
            VStack(alignment: .leading, spacing: 10) {
                Label(session.kind.title, systemImage: session.kind.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(session.kind.accent)
                if !session.label.isEmpty {
                    Text(session.label)
                        .font(.system(size: 13))
                        .foregroundStyle(NotchTokens.primaryText)
                        .lineLimit(2)
                        .frame(maxWidth: 220, alignment: .leading)
                }
                controls
            }
        }
    }

    private var stopwatchActive: some View {
        VStack(spacing: 10) {
            bigTime
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NotchTokens.primaryText)
            controls
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if state.model.isRunning {
                Button("Tạm dừng") { module.pause() }
            } else {
                Button("Tiếp tục") { module.resume() }
            }
            if state.model.isCountdown {
                Button("+1 phút") { module.addMinute() }
            }
            Button("Huỷ") { module.cancel() }
        }
    }

    @ViewBuilder private var bigTime: some View {
        switch state.model {
        case .stopwatch(let accumulated, let startedAt):
            Text(timerInterval: startedAt.addingTimeInterval(-accumulated)...Date.distantFuture, pauseTime: nil, countsDown: false)
        case .stopwatchPaused(let accumulated):
            Text(TimerFormat.clock(accumulated))
        default:
            EmptyView()
        }
    }

    // MARK: Finished

    private var finished: some View {
        let session = state.session
        return HStack(spacing: 22) {
            ZStack {
                DialRing(fraction: 1, tint: .red)
                Image(systemName: session.kind.systemImage)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.red)
            }
            .frame(width: Self.dialSize, height: Self.dialSize)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.finishedText)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Text(session.kind.title)
                        .font(.system(size: 12))
                        .foregroundStyle(NotchTokens.secondaryText)
                }
                .frame(maxWidth: 220, alignment: .leading)
                if let suggestion = module.suggestion {
                    Button(suggestion.buttonTitle) { module.startNext() }
                        .buttonStyle(.borderedProminent)
                        .tint(suggestion.kind.accent)
                }
                HStack(spacing: 8) {
                    Button("+1 phút") { module.addMinute() }
                    Button("Đóng") { module.cancel() }
                }
            }
        }
    }
}
