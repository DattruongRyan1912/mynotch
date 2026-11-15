import MyNotchCore
import SwiftUI

/// Active device telemetry and audio pipeline signal path inspection view.
public struct EQDeviceTelemetryView: View {
    public let status: EqualizerStatus
    public let isRunning: Bool
    public let openSettings: () -> Void
    public let retry: () -> Void

    public init(status: EqualizerStatus, isRunning: Bool, openSettings: @escaping () -> Void, retry: @escaping () -> Void) {
        self.status = status
        self.isRunning = isRunning
        self.openSettings = openSettings
        self.retry = retry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("GIÁM SÁT ĐƯỜNG TRUYỀN & THIẾT BỊ (SIGNAL PATH)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()

                statusIndicator
            }

            // Status message card
            HStack(spacing: 8) {
                Image(systemName: iconForStatus)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colorForStatus)

                VStack(alignment: .leading, spacing: 2) {
                    Text(status.line.text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.primary)

                    if !status.tunedDevices.isEmpty && status.activeDeviceTelemetries.isEmpty {
                        Text("Thiết bị đang xuất: \(status.tunedDevices.joined(separator: ", "))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                ForEach(status.line.actions, id: \.self) { action in
                    Button(action.title) {
                        perform(action)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(colorForStatus.opacity(0.25), lineWidth: 1)
                    )
            )

            // Active Devices Cards (Telemetry Matrix)
            if !status.activeDeviceTelemetries.isEmpty {
                VStack(spacing: 6) {
                    ForEach(status.activeDeviceTelemetries) { dev in
                        HStack(alignment: .center, spacing: 10) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(dev.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.primary)
                                Text("UID: \(dev.uid)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // Technical telemetry metrics
                            HStack(spacing: 12) {
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text("LẤY MẪU")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text(String(format: "%.0f Hz", dev.sampleRate))
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                }

                                VStack(alignment: .trailing, spacing: 1) {
                                    Text("ÂM LƯỢNG")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text(dev.volumePercent.map { "\($0)%" } ?? "N/A")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                }

                                VStack(alignment: .trailing, spacing: 1) {
                                    Text("KÊNH")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text("\(dev.channelCount) ch")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                }
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                }
            }

            // Permissions Row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quyền ghi âm thanh hệ thống (System Audio Recording)")
                        .font(.system(size: 11, weight: .medium))
                    Text("Cần để bộ lọc EQ thu nhận và xử lý tín hiệu trực tiếp từ CoreAudio.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Mở System Settings", action: openSettings)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.top, 4)
        }
    }

    private var statusIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(colorForStatus)
                .frame(width: 6, height: 6)
            Text(statusTitle)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(colorForStatus)
        }
    }

    private var statusTitle: String {
        switch status.phase {
        case .off: return "TẮT"
        case .waiting: return "CHỜ ÂM THANH"
        case .processing: return "ĐANG XỬ LÝ"
        case .needsPermission: return "THIẾU QUYỀN"
        case .failed: return "LỖI"
        }
    }

    private var iconForStatus: String {
        switch status.phase {
        case .off: return "speaker.slash"
        case .waiting: return "waveform.badge.magnifyingglass"
        case .processing: return "waveform"
        case .needsPermission: return "exclamationmark.shield"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var colorForStatus: Color {
        switch status.phase {
        case .off: return .secondary
        case .waiting: return .secondary
        case .processing: return .green
        case .needsPermission: return .red
        case .failed: return .orange
        }
    }

    private func perform(_ action: EqualizerStatus.Action) {
        switch action {
        case .openSettings: openSettings()
        case .retry: retry()
        }
    }
}
