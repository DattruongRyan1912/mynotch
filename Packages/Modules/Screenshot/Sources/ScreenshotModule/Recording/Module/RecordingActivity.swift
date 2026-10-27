import MyNotchCore
import NotchUI
import SwiftUI

/// The notch's activity for a recording: the dot and the time beside it, and under it a strip with the buttons. One activity
/// whose content changes, so the notch keeps one place for it.
enum RecordingActivity {
    static let id = "recording"
    static let stripHeight: CGFloat = 30
    /// The clock counts from the start for this long, which no recording reaches.
    static let clockSpan: TimeInterval = 100 * 3600

    static func countdown(seconds: Int, cancel: @escaping @MainActor () -> Void) -> LiveActivity {
        make(
            summary: "Quay màn hình sau \(seconds) giây",
            trailing: AnyView(Text("\(seconds)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NotchTokens.primaryText)),
            strip: AnyView(RecordingStrip(buttons: [.init(title: "Huỷ", systemImage: "xmark", tint: .gray, action: cancel)]))
        )
    }

    /// `startedAt` is when the clock reads zero (now less what was recorded), so the system advances the time by itself and the
    /// activity is published again only at a pause or a resume. `pausedAt` freezes the clock.
    static func recording(
        startedAt: Date, pausedAt: Date?, pause: @escaping @MainActor () -> Void, stop: @escaping @MainActor () -> Void
    ) -> LiveActivity {
        let isPaused = pausedAt != nil
        return make(
            summary: isPaused ? "Đã tạm dừng quay" : "Đang quay màn hình",
            isPaused: isPaused,
            trailing: AnyView(RecordingTimeText(startedAt: startedAt, pausedAt: pausedAt)),
            strip: AnyView(RecordingStrip(buttons: [
                .init(title: isPaused ? "Tiếp tục" : "Tạm dừng", systemImage: isPaused ? "play.fill" : "pause.fill", tint: .gray, action: pause),
                .init(title: "Dừng", systemImage: "stop.fill", tint: .red, action: stop),
            ]))
        )
    }

    /// The files are being closed; nothing to press.
    static func saving() -> LiveActivity {
        make(
            summary: "Đang lưu bản quay",
            trailing: AnyView(Text("Đang lưu").font(.system(size: 10, weight: .semibold)).foregroundStyle(NotchTokens.primaryText)),
            strip: nil
        )
    }

    private static func make(summary: String, isPaused: Bool = false, trailing: AnyView, strip: AnyView?) -> LiveActivity {
        LiveActivity(
            id: id, priority: .high,
            leading: AnyView(RecordingDot(isPaused: isPaused, size: 14)),
            trailing: trailing,
            bottom: strip, bottomHeight: stripHeight,
            minimal: AnyView(RecordingDot(isPaused: isPaused, size: 12)),
            summary: summary
        )
    }
}

/// The red dot of a recording; a pause sign while paused.
struct RecordingDot: View {
    let isPaused: Bool
    let size: CGFloat

    var body: some View {
        Image(systemName: isPaused ? "pause.circle.fill" : "record.circle.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(isPaused ? Color.orange : Color.red)
            .accessibilityHidden(true)
    }
}

/// The time recorded, advanced by the system 1 time per second; frozen while paused.
struct RecordingTimeText: View {
    let startedAt: Date
    let pausedAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let current = pausedAt ?? context.date
            let elapsed = max(0, current.timeIntervalSince(startedAt))
            Text(RecordingElapsed.text(elapsed))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NotchTokens.primaryText)
        }
    }
}

/// Buttons in a row under the closed notch.
struct RecordingStrip: View {
    struct Button: Identifiable {
        let title: String
        let systemImage: String
        let tint: Color
        let action: @MainActor () -> Void

        var id: String { title }
    }

    let buttons: [Button]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(buttons) { button in
                SwiftUI.Button(action: button.action) {
                    Label(button.title, systemImage: button.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NotchTokens.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(button.tint.opacity(0.35)))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// "01:23", or "1:02:03" from an hour on.
nonisolated enum RecordingElapsed {
    static func text(_ seconds: TimeInterval) -> String {
        let whole = max(Int(seconds.rounded(.down)), 0)
        let (hours, minutes, rest) = (whole / 3600, whole % 3600 / 60, whole % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%02d:%02d", minutes, rest)
    }
}
