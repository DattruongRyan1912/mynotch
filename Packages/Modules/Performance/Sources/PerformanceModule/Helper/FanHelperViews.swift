import AppKit
import NotchUI
import SwiftUI

/// One line under the fans in the tab: where the helper is, and the button for the next step. Compact: the tab has a line to spare.
struct FanHelperRow: View {
    static let height: CGFloat = 22

    /// The parts whose place a test wants to know.
    enum Part: Hashable {
        case status, button, warning
    }

    let helper: FanHelperManager
    /// Hears where each part of the line ended up, in the line's own coordinates; set by a test, nil in the app (nothing is measured).
    var report: (([Part: CGRect]) -> Void)?

    var body: some View {
        let presentation = helper.presentation
        // The button and the warning keep their natural size and come first in line for the width; the status takes what is left,
        // loses its "Helper:" before it is cut, and is cut before anything else gives. The warning is after the button, so the
        // button is never the part that is pushed out.
        HStack(spacing: 6) {
            status(presentation)
                .frame(maxWidth: .infinity, alignment: .leading)
                .measured(.status, report: report)
            if let action = presentation.primary {
                FanHelperButton(title: action.compactTitle) { run(action) }
                    .layoutPriority(2)
                    .measured(.button, report: report)
            } else if presentation.canUninstall, case .running = helper.phase {
                FanHelperButton(title: "Gỡ") { Task { await helper.uninstall() } }
                    .layoutPriority(2)
                    .measured(.button, report: report)
            }
            if let warning = presentation.warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Tone.caution.color)
                    .fixedSize()
                    .layoutPriority(2)
                    .help(warning)
                    .accessibilityLabel(warning)
                    .measured(.warning, report: report)
            }
        }
        .frame(height: Self.height)
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(PartFrames.self) { report?($0) }
        .help(presentation.tooltip)
        .accessibilityElement(children: .contain)
    }

    /// The dot and the status in words: with "Helper:" in front when there is room, without it when there is not, and cut off at the
    /// end as the last resort.
    private func status(_ presentation: FanHelperPresentation) -> some View {
        ViewThatFits(in: .horizontal) {
            statusLabel("Helper: \(presentation.shortStatus)", tone: presentation.tone, cuts: false)
            statusLabel(presentation.shortStatus, tone: presentation.tone, cuts: false)
            statusLabel(presentation.shortStatus, tone: presentation.tone, cuts: true)
        }
    }

    private func statusLabel(_ text: String, tone: Tone?, cuts: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tone?.color ?? NotchTokens.fill(0.3))
                .frame(width: 7, height: 7)
            if cuts {
                label(text)
            } else {
                label(text).fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(NotchTokens.secondaryText)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    static let space = "fanHelperRow"

    private func run(_ action: FanHelperAction) {
        switch action {
        case .install: Task { await helper.install() }
        case .openSettings: helper.openSystemSettings()
        case .retry: Task { await helper.retry() }
        }
    }
}

/// Where the parts of the line are, collected for a test.
private struct PartFrames: PreferenceKey {
    static let defaultValue: [FanHelperRow.Part: CGRect] = [:]
    static func reduce(value: inout [FanHelperRow.Part: CGRect], nextValue: () -> [FanHelperRow.Part: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    /// Reports this view's frame in the line's coordinates, when somebody listens.
    @ViewBuilder func measured(_ part: FanHelperRow.Part, report: (([FanHelperRow.Part: CGRect]) -> Void)?) -> some View {
        if report == nil {
            self
        } else {
            background(GeometryReader { proxy in
                Color.clear.preference(key: PartFrames.self, value: [part: proxy.frame(in: .named(FanHelperRow.space))])
            })
        }
    }
}

/// A small pill button in the notch's colours.
struct FanHelperButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(NotchTokens.fill(0.14)))
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// The helper's rows in Settings: where it is, the buttons for the next step, "Gỡ helper", and a way to check that what the helper
/// reads is what the app reads.
struct FanHelperSettingsRows: View {
    let helper: FanHelperManager
    /// The app's own reading of the fans, for the comparison.
    let readAppFans: () async -> [FanReading]

    var body: some View {
        let presentation = helper.presentation
        Group {
            Text("Điều khiển quạt")
                .font(.subheadline.weight(.semibold))
            LabeledContent("Helper điều khiển quạt") {
                Text(presentation.status)
                    .foregroundStyle(presentation.tone == .critical ? Tone.critical.color : .secondary)
                    .multilineTextAlignment(.trailing)
            }
            if let warning = presentation.warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Tone.caution.color)
            }
            HStack {
                if let action = presentation.primary {
                    Button(action.title) { run(action) }
                }
                if presentation.canUninstall {
                    Button("Gỡ helper", role: .destructive) { Task { await helper.uninstall() } }
                }
                if case .running = helper.phase {
                    Button("Đọc quạt qua helper") {
                        Task { await helper.compareFans(app: await readAppFans()) }
                    }
                }
            }
            .disabled(presentation.isBusy)
            if let comparison = helper.comparison {
                comparisonRows(comparison)
            }
            Text("Helper chạy với quyền root và hiện chỉ đọc quạt, chưa điều khiển được gì. Cần bấm cài và cho phép trong Cài đặt hệ thống.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { await helper.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await helper.refresh() }
        }
    }

    @ViewBuilder private func comparisonRows(_ comparison: FanComparison) -> some View {
        if let failure = comparison.failure {
            Text("Không đọc được: \(failure)").font(.caption).foregroundStyle(Tone.critical.color)
        } else if comparison.lines.isEmpty {
            Text("Helper không thấy quạt nào.").font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(comparison.lines, id: \.self) { Text($0).font(.caption).monospacedDigit() }
        }
    }

    private func run(_ action: FanHelperAction) {
        switch action {
        case .install: Task { await helper.install() }
        case .openSettings: helper.openSystemSettings()
        case .retry: Task { await helper.retry() }
        }
    }
}
