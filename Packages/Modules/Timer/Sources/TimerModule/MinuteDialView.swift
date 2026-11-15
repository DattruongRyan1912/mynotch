import AppKit
import NotchUI
import SwiftUI

/// The ring of the dial: a track, an arc from 12 o'clock for `fraction` of the hour and, while the length is being
/// set, a knob where the arc ends.
struct DialRing: View {
    static let lineWidth: CGFloat = 9

    let fraction: Double
    let tint: Color
    var showsKnob = false

    var body: some View {
        ZStack {
            Circle().stroke(NotchTokens.fill(0.12), lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showsKnob {
                // A round cap on an arc of no length is a dot, so the knob needs no geometry of its own.
                Circle()
                    .trim(from: max(fraction - 0.001, 0), to: max(fraction, 0.001))
                    .stroke(NotchTokens.primaryText, style: StrokeStyle(lineWidth: Self.lineWidth + 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(Self.lineWidth / 2 + 3)
    }
}

/// The dial while idle: drag round the ring, scroll over it, or use ←/→ (⇧ for five) to set whole minutes.
struct MinuteSettingDial: View {
    let kind: TimerKind
    let minutes: Int
    let size: CGFloat
    var focus: FocusState<Bool>.Binding
    let set: (Int) -> Void

    var body: some View {
        ZStack {
            DialRing(fraction: Double(minutes) / 60, tint: kind.accent, showsKnob: true)
            VStack(spacing: 0) {
                Text("\(minutes)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(NotchTokens.primaryText)
                Text("phút")
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTokens.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(kind.accent.opacity(0.4), lineWidth: 1).opacity(focus.wrappedValue ? 1 : 0))
        .contentShape(Circle())
        .overlay { ScrollWheelCatcher { step($0) } }
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag(to: $0.location) })
        .focusable()
        .focused(focus)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { press in
            guard press.key == .leftArrow || press.key == .rightArrow else { return .ignored }
            step(MinuteDial.keyboardDelta(increase: press.key == .rightArrow, shift: press.modifiers.contains(.shift)))
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Số phút \(kind.title.lowercased())")
        .accessibilityValue(MinuteDial.spokenSetting(minutes: minutes))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
    }

    private func drag(to location: CGPoint) {
        focus.wrappedValue = true
        let angle = MinuteDial.angle(of: location, around: CGPoint(x: size / 2, y: size / 2))
        set(MinuteDial.minutes(forAngle: angle, previous: minutes))
    }

    private func step(_ delta: Int) {
        set(MinuteDial.stepped(minutes, by: delta))
    }
}

/// The dial while a countdown runs or is paused: the same ring, now showing the time left, with the clock in its middle.
struct RunningDial: View {
    static let ringInterval: TimeInterval = 5

    let model: TimerModel
    let session: TimerSession
    let size: CGFloat

    var body: some View {
        if case .countdown = model {
            // The ring moves a tenth of a point a second and the clock inside counts by itself, so a few seconds
            // between redraws is enough, and none at all while the notch is off screen.
            NotchTimeline(every: Self.ringInterval) { dial(remaining: model.remaining(now: $0)) }
        } else {
            dial(remaining: model.remaining(now: .now))
        }
    }

    private func dial(remaining: TimeInterval) -> some View {
        ZStack {
            DialRing(fraction: MinuteDial.fraction(remaining: remaining), tint: session.kind.accent)
            clock
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(NotchTokens.primaryText)
                .padding(.horizontal, 18)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.summary)
        .accessibilityValue(MinuteDial.spokenRemaining(seconds: remaining))
    }

    @ViewBuilder private var clock: some View {
        switch model {
        case .countdown(let endDate):
            Text(timerInterval: TimerTabView.countdownRange(to: endDate), pauseTime: nil, countsDown: true)
        case .countdownPaused(let remaining):
            Text(TimerFormat.clock(remaining))
        default:
            EmptyView()
        }
    }
}

/// Hands the scroll over the dial to `onScroll`, as whole minutes. It takes only scroll events, and of those only the up
/// and down ones (`DialScrollGate`): every click and drag falls through to the SwiftUI dial beneath it, and the rest of
/// the scrolling goes on up the responder chain, where the notch turns a sideways swipe into a tab change.
struct ScrollWheelCatcher: NSViewRepresentable {
    let onScroll: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) { view.onScroll = onScroll }

    final class CatcherView: NSView {
        var onScroll: ((Int) -> Void)?
        private var gate = DialScrollGate()

        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp?.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
        }

        override func scrollWheel(with event: NSEvent) {
            let action = gate.feed(
                phase: event.phase, momentumPhase: event.momentumPhase, deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY, isPrecise: event.hasPreciseScrollingDeltas)
            switch action {
            case .forward: super.scrollWheel(with: event)
            case .consume: break
            case .minutes(let minutes): onScroll?(minutes)
            }
        }
    }
}
