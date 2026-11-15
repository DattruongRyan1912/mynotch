import BatteryModule
import EqualizerModule
import HabitModule
import MyNotchCore
import NotchUI
import Observation
import SwiftUI
import TodoModule

enum DashboardTab: RawRepresentable, CaseIterable, Identifiable, Equatable, Sendable {
    case overview
    case battery
    case todo
    case hardware
    case audio
    case productivity
    case cleaner
    case modules

    nonisolated var id: String { rawValue }

    nonisolated var rawValue: String {
        switch self {
        case .overview: return "overview"
        case .battery: return "battery"
        case .todo: return "todo"
        case .hardware: return "hardware"
        case .audio: return "audio"
        case .productivity: return "productivity"
        case .cleaner: return "cleaner"
        case .modules: return "modules"
        }
    }

    nonisolated init?(rawValue: String) {
        switch rawValue {
        case "overview": self = .overview
        case "battery": self = .battery
        case "todo": self = .todo
        case "hardware": self = .hardware
        case "audio", "sound", "equalizer": self = .audio
        case "productivity": self = .productivity
        case "cleaner", "workspace": self = .cleaner
        case "modules": self = .modules
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .overview: return "Tổng quan"
        case .battery: return "Pin & Năng lượng"
        case .todo: return "Việc cần làm"
        case .hardware: return "Phần cứng"
        case .audio: return "Âm thanh & EQ"
        case .productivity: return "Năng suất & Thói quen"
        case .cleaner: return "Dọn dẹp & Tối ưu"
        case .modules: return "Mô-đun"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .battery: return "battery.100percent.bolt"
        case .todo: return "checklist"
        case .hardware: return "cpu"
        case .audio: return "slider.vertical.3"
        case .productivity: return "flame.fill"
        case .cleaner: return "trash"
        case .modules: return "shippingbox"
        }
    }

    var iconColor: Color {
        switch self {
        case .overview: return DashboardTheme.infoAccent
        case .battery: return DashboardTheme.batteryGreen
        case .todo: return DashboardTheme.todoBlue
        case .hardware: return DashboardTheme.hardwareCoral
        case .audio: return DashboardTheme.infoAccent
        case .productivity: return DashboardTheme.habitViolet
        case .cleaner: return DashboardTheme.hardwareCoral
        case .modules: return DashboardTheme.textSecondary
        }
    }
}

@Observable
@MainActor
final class DashboardNavigationState {
    var selectedTab: DashboardTab = .overview
    var lastRefreshed: Date = Date()
}

struct DashboardRootView: View {
    let telemetry: DashboardTelemetryCenter
    let registry: ModuleRegistry
    var nav: DashboardNavigationState
    let openSettings: () -> Void
    @ObservedObject var themeStore: DashboardThemeStore = .shared
    var toastCenter: DashboardToastCenter = .shared

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar Navigation (Soft UI Scandinavian style)
            sidebar
                .frame(width: 230)
                .background(DashboardTheme.sidebarBackground)

            Rectangle()
                .fill(DashboardTheme.hairlineBorder)
                .frame(width: 1)

            // Content Canvas
            VStack(spacing: 0) {
                // Top Telemetry Header
                topHeader
                    .frame(height: 52)
                    .background(TitlebarDoubleClickArea())
                    .background(DashboardTheme.headerBackground)

                Rectangle()
                    .fill(DashboardTheme.hairlineBorder)
                    .frame(height: 1)

                // Tab Content Body
                Group {
                    switch nav.selectedTab {
                    case .overview:
                        DashboardOverviewView(telemetry: telemetry) { tab in
                            nav.selectedTab = tab
                        }
                    case .battery:
                        DashboardBatteryStudioView(telemetry: telemetry, registry: registry)
                    case .todo:
                        DashboardTodoStudioView(telemetry: telemetry, registry: registry)
                    case .hardware:
                        DashboardHardwareView(telemetry: telemetry)
                    case .audio:
                        DashboardAudioStudioView(telemetry: telemetry, registry: registry)
                    case .productivity:
                        DashboardProductivityView(telemetry: telemetry, registry: registry)
                    case .cleaner:
                        DashboardCleanerStudioView(telemetry: telemetry, registry: registry)
                    case .modules:
                        DashboardModulesView(registry: registry)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DashboardTheme.canvasBackground)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 920, minHeight: 600)
        .overlay(DashboardToastOverlayView(toastCenter: toastCenter))
        .background(
            Group {
                if themeStore.style == .liquidGlass {
                    ZStack {
                        DashboardVisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow)
                        DashboardTheme.rootWash
                    }
                    .ignoresSafeArea()
                } else {
                    DashboardTheme.canvasBackground
                        .ignoresSafeArea()
                }
            }
        )
        .id(themeStore.style)
        .environment(\.colorScheme, .light)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sidebar Header / Brand
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(DashboardTheme.infoAccent)
                    .frame(width: 10, height: 10)

                Text("MYNOTCH")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DashboardTheme.textPrimary)

                Text("STUDIO")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DashboardTheme.infoAccent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(DashboardTheme.infoAccent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .background(TitlebarDoubleClickArea())

            // Nav Items
            VStack(spacing: 4) {
                ForEach(DashboardTab.allCases) { tab in
                    let isSelected = nav.selectedTab == tab

                    Button {
                        nav.selectedTab = tab
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(
                                    isSelected
                                        ? (themeStore.style == .stripeLight ? Color(red: 29/255, green: 78/255, blue: 216/255) : tab.iconColor)
                                        : DashboardTheme.textSecondary
                                )
                                .frame(width: 18)

                            Text(tab.title)
                                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                                .foregroundColor(
                                    isSelected
                                        ? (themeStore.style == .stripeLight ? Color(red: 29/255, green: 78/255, blue: 216/255) : DashboardTheme.textPrimary)
                                        : DashboardTheme.textSecondary
                                )

                            Spacer()

                            tabBadge(for: tab)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if isSelected {
                                    switch themeStore.style {
                                    case .softUI:
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.white)
                                            .shadow(color: Color(red: 15/255, green: 23/255, blue: 42/255).opacity(0.08), radius: 6, x: 0, y: 2)
                                    case .liquidGlass:
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(DashboardTheme.navActiveBackground)
                                            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 1)
                                    case .stripeLight:
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color(red: 239/255, green: 246/255, blue: 255/255))
                                    }
                                } else {
                                    Color.clear
                                }
                            }
                        )
                        .overlay(
                            Group {
                                if isSelected {
                                    switch themeStore.style {
                                    case .softUI:
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(DashboardTheme.hairlineBorder, lineWidth: 1)
                                    case .liquidGlass:
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(DashboardTheme.hairlineBorder, lineWidth: 1)
                                    case .stripeLight:
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color(red: 191/255, green: 219/255, blue: 254/255), lineWidth: 1)
                                    }
                                }
                            }
                        )
                        .overlay(alignment: .leading) {
                            if isSelected && themeStore.style == .stripeLight {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(DashboardTheme.infoAccent)
                                    .frame(width: 3)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            // System Information Footer
            VStack(alignment: .leading, spacing: 6) {
                Rectangle()
                    .fill(DashboardTheme.hairlineBorder)
                    .frame(height: 1)
                    .padding(.bottom, 6)

                HStack {
                    Text("HỆ THỐNG")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DashboardTheme.textMuted)
                    Spacer()
                    Text("Apple Silicon")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(DashboardTheme.textSecondary)
                }

                HStack {
                    Text("PHIÊN BẢN")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DashboardTheme.textMuted)
                    Spacer()
                    Text("0.1.0 (Build 1)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(DashboardTheme.textSecondary)
                }

                Button {
                    openSettings()
                } label: {
                    HStack {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11))
                        Text("Cài đặt MyNotch…")
                            .font(.system(size: 11.5, weight: .medium))
                        Spacer()
                    }
                    .foregroundColor(DashboardTheme.textSecondary)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private func tabBadge(for tab: DashboardTab) -> some View {
        if tab == .modules {
            Text("\(registry.modules.count)")
                .font(.system(size: 10.5, weight: .bold))
                .monospacedDigit()
                .foregroundColor(DashboardTheme.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DashboardTheme.chipBackground)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else if tab == .audio {
            if let eqModule = registry.module(for: "equalizer") as? EqualizerModule {
                let count = eqModule.appVolumeState.runningApps.count
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(DashboardTheme.infoAccent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DashboardTheme.chipBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        } else if tab == .cleaner {
            let cleanable = registry.storageCenter.cleanableBytes
            if cleanable > 0 {
                Text(DashboardTheme.formatBytes(cleanable))
                    .font(.system(size: 9.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(DashboardTheme.hardwareCoral)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(DashboardTheme.chipBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    // MARK: - Top Header (Clean Scandinavian Soft UI)

    private var topHeader: some View {
        HStack(spacing: 12) {
            // Elevated Primary Title (Clean UI - Title lên cao)
            HStack(spacing: 8) {
                Image(systemName: nav.selectedTab.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(nav.selectedTab.iconColor)

                Text(nav.selectedTab.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(DashboardTheme.textPrimary)
            }

            Spacer()

            // Contextual Accessory Badges
            tabTrailingAccessory
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var tabTrailingAccessory: some View {
        switch nav.selectedTab {
        case .productivity:
            if let habitModule = registry.module(for: "habit") as? HabitModule {
                let metrics = habitModule.state.headerMetrics()

                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundColor(DashboardTheme.statusDegraded)
                        Text("Streak đỉnh: \(metrics.maxStreak) ngày")
                            .font(.system(size: 11.5, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(DashboardTheme.textPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DashboardTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DashboardTheme.hairlineBorder, lineWidth: 1)
                    )

                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(metrics.doneToday == metrics.totalHabits && metrics.totalHabits > 0 ? DashboardTheme.statusNormal : DashboardTheme.infoAccent)
                        Text("Hôm nay: \(metrics.doneToday)/\(metrics.totalHabits)")
                            .font(.system(size: 11.5, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(DashboardTheme.textPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DashboardTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DashboardTheme.hairlineBorder, lineWidth: 1)
                    )
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        case .todo:
            if let todoModule = registry.module(for: "todo") as? TodoModule {
                let tasks = todoModule.studioTasks
                let completed = tasks.filter { $0.isCompleted }.count
                let total = tasks.count

                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.system(size: 11))
                        .foregroundColor(completed == total && total > 0 ? DashboardTheme.statusNormal : DashboardTheme.infoAccent)
                    Text("Hôm nay: \(completed)/\(total) hoàn thành")
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(DashboardTheme.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DashboardTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(DashboardTheme.hairlineBorder, lineWidth: 1)
                )
                .fixedSize(horizontal: true, vertical: false)
            }
        case .battery:
            if let batteryModule = registry.module(for: "battery") as? BatteryModule {
                let isReady = batteryModule.helperStatus == .enabled
                HStack(spacing: 6) {
                    Circle()
                        .fill(isReady ? DashboardTheme.statusNormal : DashboardTheme.statusDegraded)
                        .frame(width: 7, height: 7)
                    Text(isReady ? "SMC Daemon: Hoạt động" : "SMC Helper: Cần cấp quyền")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(DashboardTheme.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DashboardTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(DashboardTheme.hairlineBorder, lineWidth: 1)
                )
                .fixedSize(horizontal: true, vertical: false)
            }
        default:
            EmptyView()
        }
    }
}
