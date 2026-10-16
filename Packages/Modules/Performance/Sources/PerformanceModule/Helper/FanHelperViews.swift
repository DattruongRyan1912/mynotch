import AppKit
import NotchUI
import SwiftUI

/// One line under the fans in the tab: where the helper is, and the button for the next step. Compact: the tab has a line to spare.
struct FanHelperRow: View {
    static let height: CGFloat = 22

    let helper: FanHelperManager

    var body: some View {
        let presentation = helper.presentation
        HStack(spacing: 6) {
            Circle()
                .fill(presentation.tone?.color ?? NotchTokens.fill(0.3))
                .frame(width: 7, height: 7)
            Text("Helper: \(presentation.shortStatus)")
                .font(.system(size: 11))
                .foregroundStyle(NotchTokens.secondaryText)
                .lineLimit(1)
            if let warning = presentation.warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Tone.caution.color)
                    .help(warning)
                    .accessibilityLabel(warning)
            }
            Spacer(minLength: 4)
            if let action = presentation.primary {
                FanHelperButton(title: action.compactTitle) { run(action) }
            } else if presentation.canUninstall, case .running = helper.phase {
                FanHelperButton(title: "Gỡ") { Task { await helper.uninstall() } }
            }
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .contain)
    }

    private func run(_ action: FanHelperAction) {
        switch action {
        case .install: Task { await helper.install() }
        case .openSettings: helper.openSystemSettings()
        case .retry: Task { await helper.retry() }
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
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(NotchTokens.fill(0.14)))
        }
        .buttonStyle(.plain)
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
