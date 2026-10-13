import MyNotchCore
import NotchUI
import SwiftUI

enum TimerActivity {
    static func running(systemImage: String, range: ClosedRange<Date>, countsDown: Bool) -> LiveActivity {
        LiveActivity(
            id: TimerModule.activityID,
            leading: AnyView(Image(systemName: systemImage).font(.system(size: 14, weight: .semibold)).foregroundStyle(.orange)),
            trailing: AnyView(
                Text(timerInterval: range, pauseTime: nil, countsDown: countsDown)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            )
        )
    }

    static func finished(expiresAfter: Duration) -> LiveActivity {
        LiveActivity(
            id: TimerModule.activityID,
            priority: .high,
            expiresAfter: expiresAfter,
            leading: AnyView(Image(systemName: "hourglass.bottomhalf.filled").font(.system(size: 14, weight: .semibold)).foregroundStyle(.red)),
            trailing: AnyView(Text("Hết giờ").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.red))
        )
    }
}

/// Lock screen widget: the remaining time of a running countdown and nothing else.
struct TimerLockScreenView: View {
    let endDate: Date

    var range: ClosedRange<Date> { TimerTabView.countdownRange(to: endDate) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: 20, weight: .semibold))
            Text(timerInterval: range, pauseTime: nil, countsDown: true)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.orange)
    }
}

/// The "Hẹn giờ" tab: presets while idle, otherwise the big time and its controls.
struct TimerTabView: View {
    static let presets = [1, 5, 10, 25]

    /// Counts down to `endDate` from a lower bound that never moves, so rebuilding the view cannot restart the text.
    static func countdownRange(to endDate: Date) -> ClosedRange<Date> { .distantPast...endDate }

    let state: TimerState
    let module: TimerModule

    var body: some View {
        VStack(spacing: 10) {
            switch state.model {
            case .idle: idle
            case .finished: finished
            default: active
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idle: some View {
        @Bindable var state = state
        return VStack(spacing: 10) {
            Picker("Chế độ", selection: $state.mode) {
                Text("Đếm ngược").tag(TimerState.Mode.countdown)
                Text("Bấm giờ").tag(TimerState.Mode.stopwatch)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            if state.mode == .countdown {
                HStack(spacing: 8) {
                    ForEach(Self.presets, id: \.self) { minutes in
                        Button("\(minutes) phút") { module.startCountdown(minutes: minutes) }
                    }
                }
                HStack(spacing: 10) {
                    Stepper("\(state.customMinutes) phút", value: $state.customMinutes, in: 1...180)
                        .foregroundStyle(NotchTokens.primaryText)
                    Button("Bắt đầu") { module.startCountdown(minutes: state.customMinutes) }
                }
            } else {
                Text("0:00")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchTokens.secondaryText)
                Button("Bắt đầu") { module.startStopwatch() }
            }
        }
    }

    private var finished: some View {
        VStack(spacing: 10) {
            Text("Hết giờ")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundStyle(.red)
            HStack(spacing: 8) {
                Button("+1 phút") { module.addMinute() }
                Button("Đóng") { module.cancel() }
            }
        }
    }

    private var active: some View {
        VStack(spacing: 10) {
            bigTime
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NotchTokens.primaryText)
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
    }

    @ViewBuilder private var bigTime: some View {
        switch state.model {
        case .countdown(let endDate):
            Text(timerInterval: Self.countdownRange(to: endDate), pauseTime: nil, countsDown: true)
        case .stopwatch(let accumulated, let startedAt):
            Text(timerInterval: startedAt.addingTimeInterval(-accumulated)...Date.distantFuture, pauseTime: nil, countsDown: false)
        case .countdownPaused(let remaining):
            Text(TimerFormat.clock(remaining))
        case .stopwatchPaused(let accumulated):
            Text(TimerFormat.clock(accumulated))
        default:
            EmptyView()
        }
    }
}
