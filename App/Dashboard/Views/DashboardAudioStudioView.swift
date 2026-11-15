import AppKit
import EqualizerAudio
import EqualizerDSP
import EqualizerModule
import MediaModule
import MyNotchCore
import SwiftUI

/// Dedicated full-screen studio for Audio Management, Per-App Volume Mixer, and Master Equalizer.
/// Follows Scandinavian Soft UI / Dark Zinc 950 design standards with zero AI-slop.
struct DashboardAudioStudioView: View {
    let telemetry: DashboardTelemetryCenter
    let registry: ModuleRegistry

    private var equalizerModule: EqualizerModule? {
        registry.module(for: "equalizer") as? EqualizerModule
    }

    private var state: EqualizerState? {
        equalizerModule?.equalizerState
    }

    private var status: EqualizerStatus? {
        equalizerModule?.equalizerStatus
    }

    private var appVolumeState: AppVolumeState? {
        equalizerModule?.appVolumeState
    }

    private var appVolumeMonitor: AppAudioProcessMonitor? {
        equalizerModule?.appVolumeMonitor
    }

    private var runningApps: [RunningAudioApp] {
        appVolumeState?.runningApps ?? []
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                // Section 1: Top Header & Key Audio Telemetry Cards
                overviewHeaderSection

                // Section 2: Per-App Volume Mixer
                perAppMixerSection

                // Section 3: Master Equalizer Studio
                if let state = state {
                    masterEqualizerSection(state: state)
                }

                // Section 4: True-Peak Limiter & Signal Path Telemetry
                if let state = state, let status = status {
                    signalPathAndLimiterSection(state: state, status: status)
                }
            }
            .padding(20)
        }
        .background(DashboardTheme.canvasBackground)
        .onAppear {
            if appVolumeMonitor?.chromeVolumeDispatcher == nil {
                let media = registry.module(for: "media") as? MediaModule
                appVolumeMonitor?.chromeVolumeDispatcher = { [weak media] volume, isMuted in
                    media?.sendChromeVolume(volume: volume, isMuted: isMuted) ?? false
                }
            }
            appVolumeMonitor?.refresh()
        }
    }

    // MARK: - Section 1: Overview & KPI Cards

    private var overviewHeaderSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                DashboardSectionHeader(
                    title: "Âm thanh & EQ Studio",
                    subtitle: "Bộ trộn âm lượng từng ứng dụng và cân chỉnh tần số chuẩn phòng thu"
                )

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        appVolumeMonitor?.refresh()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Quét lại nguồn phát")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundColor(DashboardTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(DashboardTheme.insetBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(DashboardTheme.hairlineBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Top KPI Cards Grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ], spacing: 12) {
                // 1. Output Device
                let deviceName = status?.activeDeviceTelemetries.first?.name ?? "Loa mặc định"
                DashboardMetricCard(
                    label: "Thiết bị đầu ra",
                    value: deviceName,
                    icon: "speaker.wave.3",
                    level: .normal,
                    subtitle: status?.activeDeviceTelemetries.first.map { "\($0.channelCount) kênh • \(String(format: "%.1f", $0.sampleRate / 1000.0)) kHz" } ?? "CoreAudio output"
                )

                // 2. EQ Processing Status
                let isEqActive = (state?.activeProfile != nil) && (status?.isRunning ?? false)
                DashboardMetricCard(
                    label: "Trạng thái EQ",
                    value: isEqActive ? "Đang bật" : "Tạm dừng",
                    icon: "slider.vertical.3",
                    level: isEqActive ? .success : .normal,
                    subtitle: status?.line.text ?? "Sẵn sàng"
                )

                // 3. True-Peak Ceiling
                let ceiling = state?.ceilingDBTP ?? -0.5
                DashboardMetricCard(
                    label: "Trần True-Peak",
                    value: String(format: "%.1f", ceiling),
                    unit: "dBTP",
                    icon: "waveform.path.badge.minus",
                    level: .normal,
                    subtitle: "Bảo vệ chống méo tiếng liên mẫu"
                )

                // 4. Active Audio Apps
                let appCount = runningApps.count
                DashboardMetricCard(
                    label: "Nguồn phát đang chạy",
                    value: "\(appCount)",
                    unit: "ứng dụng",
                    icon: "app.connected.to.app.below.fill",
                    level: appCount > 0 ? .success : .normal,
                    subtitle: appCount > 0 ? "\(runningApps.map(\.name).prefix(2).joined(separator: ", "))" : "Chưa có luồng phát"
                )
            }
        }
    }

    // MARK: - Section 2: Per-App Volume Mixer

    private var perAppMixerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.2.square")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DashboardTheme.infoAccent)
                    Text("BỘ TRỘN ÂM LƯỢNG ỨNG DỤNG (PER-APP MIXER)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(DashboardTheme.textSecondary)
                }

                Spacer()

                if !runningApps.isEmpty {
                    Button("Khôi phục tất cả về 100%") {
                        appVolumeState?.resetAll()
                        for app in runningApps {
                            appVolumeMonitor?.resetVolume(for: app)
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DashboardTheme.textSecondary)
                    .buttonStyle(.plain)
                }
            }

            if runningApps.isEmpty {
                emptyMixerState
            } else {
                VStack(spacing: 8) {
                    ForEach(runningApps) { app in
                        appVolumeRow(app: app)
                    }
                }
            }
        }
        .padding(16)
        .background(DashboardTheme.insetBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardTheme.hairlineBorder, lineWidth: 1)
        )
    }

    private var emptyMixerState: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 20))
                .foregroundColor(DashboardTheme.textSecondary.opacity(0.6))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text("Hiện không có ứng dụng nào đang phát âm thanh")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(DashboardTheme.textPrimary)
                Text("Mở Spotify, Apple Music, YouTube hoặc trình phát bất kỳ để điều chỉnh âm lượng riêng biệt.")
                    .font(.system(size: 11))
                    .foregroundColor(DashboardTheme.textSecondary)
            }

            Spacer()

            Button("Làm mới") {
                appVolumeMonitor?.refresh()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(DashboardTheme.infoAccent)
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(DashboardTheme.canvasBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func appVolumeRow(app: RunningAudioApp) -> some View {
        let rawVol = appVolumeState?.rawVolume(for: app.id) ?? 1.0
        let isMuted = appVolumeState?.isMuted(for: app.id) ?? false

        return HStack(spacing: 12) {
            // App Icon
            appIcon(for: app)
                .frame(width: 28, height: 28)

            // App Name & Bundle ID
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(DashboardTheme.textPrimary)
                        .lineLimit(1)

                    if !app.isControllable {
                        Text("CHỈ ĐỌC")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(DashboardTheme.chipBackground)
                            .foregroundColor(DashboardTheme.textSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .help("macOS không cho phép điều chỉnh âm lượng riêng của ứng dụng này khi không có trình điều khiển âm thanh ảo.")
                    } else if app.controlNotice != nil {
                        Text("CẦN BẬT QUYỀN")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(DashboardTheme.hardwareCoral.opacity(0.15))
                            .foregroundColor(DashboardTheme.hardwareCoral)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                }

                if let notice = app.controlNotice, app.isControllable {
                    Text(notice)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DashboardTheme.hardwareCoral)
                        .lineLimit(1)
                        .help(notice)
                } else {
                    Text(app.bundleID ?? "PID \(app.pid)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(DashboardTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 175, alignment: .leading)

            // Volume Slider (0% to 150%)
            Slider(
                value: Binding(
                    get: { rawVol },
                    set: { newVol in
                        appVolumeMonitor?.setVolume(newVol, for: app)
                    }
                ),
                in: 0.0...1.5,
                step: 0.05
            )
            .controlSize(.small)
            .opacity((isMuted || !app.isControllable) ? 0.4 : 1.0)
            .disabled(!app.isControllable)

            // Percentage readout (monospaced tabular-nums)
            Text(!app.isControllable ? "--" : (isMuted ? "TẮT" : "\(Int((rawVol * 100.0).rounded()))%"))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(!app.isControllable ? DashboardTheme.textSecondary : (isMuted ? DashboardTheme.hardwareCoral : (rawVol > 1.0 ? DashboardTheme.todoBlue : DashboardTheme.textPrimary)))
                .frame(width: 44, alignment: .trailing)

            // Mute / Unmute Button
            Button {
                appVolumeMonitor?.toggleMute(for: app)
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isMuted ? DashboardTheme.hardwareCoral : DashboardTheme.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(DashboardTheme.chipBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!app.isControllable)
            .opacity(app.isControllable ? 1.0 : 0.4)
            .help(!app.isControllable ? "Ứng dụng này chỉ hỗ trợ hiển thị mức, không hỗ trợ tắt tiếng." : (isMuted ? "Bật lại tiếng" : "Tắt tiếng ứng dụng này"))

            // Reset to 100% Button
            if app.isControllable && (rawVol != 1.0 || isMuted) {
                Button {
                    appVolumeMonitor?.resetVolume(for: app)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DashboardTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(DashboardTheme.chipBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Khôi phục về 100%")
            } else {
                Spacer()
                    .frame(width: 26)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DashboardTheme.canvasBackground.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(DashboardTheme.hairlineBorder.opacity(0.6), lineWidth: 1)
        )
    }

    private func appIcon(for app: RunningAudioApp) -> some View {
        Group {
            if let runningIcon = NSRunningApplication(processIdentifier: app.pid)?.icon {
                Image(nsImage: runningIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let bundleID = app.bundleID,
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 16))
                    .foregroundColor(DashboardTheme.textSecondary)
            }
        }
    }

    // MARK: - Section 3: Master Equalizer Studio

    private func masterEqualizerSection(state: EqualizerState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DashboardTheme.infoAccent)
                Text("BỘ CÂN CHỈNH TẦN SỐ (MASTER EQUALIZER STUDIO)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(DashboardTheme.textSecondary)
            }

            // Presets Selector & CRUD Toolbar
            EQPresetLibraryView(state: state)

            // Frequency Response Curve Simulation
            if let profile = state.selected {
                EQResponseCurveView(profile: profile)
            }

            // 10-Band Sliders & Preamp
            EQProfileEditorView(state: state)
        }
        .padding(16)
        .background(DashboardTheme.insetBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardTheme.hairlineBorder, lineWidth: 1)
        )
    }

    // MARK: - Section 4: True-Peak Limiter & Signal Path Telemetry

    private func signalPathAndLimiterSection(state: EqualizerState, status: EqualizerStatus) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Processing Settings (Limiter Ceiling & Dynamic Loudness)
            EQProcessingSettingsView(state: state)

            Divider()
                .background(DashboardTheme.hairlineBorder)

            // Signal Path & Live Device Telemetries
            EQDeviceTelemetryView(
                status: status,
                isRunning: status.isRunning,
                openSettings: {
                    equalizerModule?.openSystemSettings()
                },
                retry: {
                    equalizerModule?.retry()
                }
            )
        }
        .padding(16)
        .background(DashboardTheme.insetBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardTheme.hairlineBorder, lineWidth: 1)
        )
    }
}
