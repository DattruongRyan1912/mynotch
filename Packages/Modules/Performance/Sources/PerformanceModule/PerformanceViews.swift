import NotchUI
import SwiftUI

extension Tone {
    /// The colours macOS itself uses for good, careful and bad.
    var color: Color {
        switch self {
        case .normal: Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
        case .caution: Color(red: 1, green: 0x9F / 255, blue: 0x0A / 255)
        case .critical: Color(red: 1, green: 0x45 / 255, blue: 0x3A / 255)
        }
    }
}

/// The "Hiệu năng" tab.
struct PerformanceTabView: View {
    /// What the tab's content needs, with room to spare; a test checks the content fits it at the narrowest notch.
    static let contentHeight: CGFloat = 192
    /// The tab bar's height when there are two or more tabs; `NotchTab.preferredHeight` includes it.
    static let tabBarHeight: CGFloat = 30
    static var preferredHeight: CGFloat { contentHeight + NotchTokens.padding + tabBarHeight }

    let state: PerformanceState
    let actions: PerformanceTabActions

    var body: some View {
        PerformanceColumns(state: state)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear(perform: actions.appeared)
            .onDisappear(perform: actions.disappeared)
    }
}

/// The temperatures on the left and the memory on the right; the memory alone on a Mac with no sensors to read.
struct PerformanceColumns: View {
    static let spacing: CGFloat = 20

    let state: PerformanceState

    var body: some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            if state.hasThermal {
                ThermalColumn(state: state).frame(maxWidth: .infinity, alignment: .top)
            }
            MemoryColumn(state: state).frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

/// The SoC temperature large, the CPU and GPU beside it, the last two minutes as a line, and a row per fan.
struct ThermalColumn: View {
    let state: PerformanceState
    @State private var showSensorsDetail = false

    var body: some View {
        let presentation = ThermalPresentation(state.thermal)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(presentation.tone?.color ?? NotchTokens.fill(0.3))
                    .frame(width: 7, height: 7)
                Text("SoC")
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTokens.secondaryText)
                if presentation.sensorCount > 0 {
                    sensorsBadge(presentation)
                }
                Spacer(minLength: 6)
                if let cpuUsage = state.cpuUsage {
                    Text("\(Int(cpuUsage.rounded()))% CPU")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(NotchTokens.primaryText)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.accessibilityLabel + (state.cpuUsage.map { ", CPU \($0.rounded())%" } ?? ""))

            HStack(alignment: .top, spacing: 14) {
                summary(presentation)
                VStack(alignment: .leading, spacing: 2) {
                    ThermalSparkline(history: state.thermal == nil ? ThermalHistory() : state.history, tone: presentation.tone)
                        .frame(height: 44)
                    Text("2 phút gần nhất")
                        .font(.system(size: 10))
                        .foregroundStyle(NotchTokens.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            }
            if !presentation.fans.isEmpty {
                VStack(spacing: 8) {
                    ForEach(presentation.fans) { FanRowView(row: $0) }
                    if let helper = state.helper { FanHelperRow(helper: helper, curveText: state.curve?.activeText) }
                }
            }
        }
    }

    @ViewBuilder private func sensorsBadge(_ presentation: ThermalPresentation) -> some View {
        Button(action: { showSensorsDetail = true }) {
            HStack(spacing: 2.5) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 7))
                Text("\(presentation.sensorCount)")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .monospacedDigit()
            }
            .foregroundStyle(NotchTokens.secondaryText)
            .padding(.horizontal, 3.5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(NotchTokens.fill(0.18), lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(NotchTokens.fill(0.08)))
            )
        }
        .buttonStyle(.plain)
        .help("Xem chi tiết \(presentation.sensorCount) cảm biến nhiệt IOHID")
        .popover(isPresented: $showSensorsDetail, arrowEdge: .bottom) {
            SensorsDetailPopoverView(presentation: presentation)
        }
    }

    private func summary(_ presentation: ThermalPresentation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(presentation.soc)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NotchTokens.primaryText)
            HStack(spacing: 10) {
                die("CPU", presentation.cpu)
                die("GPU", presentation.gpu)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func die(_ name: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(name).foregroundStyle(NotchTokens.secondaryText)
            Text(value).foregroundStyle(NotchTokens.primaryText).monospacedDigit()
        }
        .font(.system(size: 11))
    }
}

/// A fan: its speed in words and a bar between its minimum and maximum.
struct FanRowView: View {
    let row: FanRow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text(row.title)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTokens.secondaryText)
                Spacer(minLength: 6)
                Text(row.rpm)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(NotchTokens.primaryText)
                Text(" vòng/phút")
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTokens.secondaryText)
            }
            HStack(spacing: 8) {
                FanBar(fraction: row.fraction)
                Text(row.range)
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(NotchTokens.secondaryText)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

struct FanBar: View {
    static let height: CGFloat = 4
    let fraction: Double

    var body: some View {
        let track = NotchTokens.fill(0.18)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(NotchTokens.accent).frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: Self.height)
    }
}

/// The SoC temperature over the last two minutes, newest at the right. A line per run of samples, so a pause is a gap.
struct ThermalSparkline: View {
    /// A gap between samples longer than this (the poll is two seconds) is a pause, not a slow read.
    nonisolated static let maxGap: TimeInterval = 5
    nonisolated static let inset: CGFloat = 3

    let history: ThermalHistory
    let tone: Tone?

    var body: some View {
        let line = tone?.color ?? NotchTokens.accent
        let baseline = NotchTokens.fill(0.2)
        Canvas { context, size in
            context.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)), with: .color(baseline))
            guard let scale = history.scale else { return }
            func point(_ sample: ThermalHistory.Sample) -> CGPoint {
                let height = size.height - 2 * Self.inset
                let level = (sample.value - scale.lowerBound) / (scale.upperBound - scale.lowerBound)
                return CGPoint(x: history.position(of: sample) * size.width, y: Self.inset + height * (1 - level))
            }
            for run in history.runs(maxGap: Self.maxGap) {
                var path = Path()
                for (index, sample) in run.enumerated() {
                    index == 0 ? path.move(to: point(sample)) : path.addLine(to: point(sample))
                }
                context.stroke(path, with: .color(line), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if run.count == 1, let only = run.first {
                    let center = point(only)
                    context.fill(Path(ellipseIn: CGRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3)), with: .color(line))
                }
            }
            if let newest = history.samples.last {
                let center = point(newest)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)), with: .color(line))
            }
        }
    }
}

/// Detailed inspector for 30+ IOHID hardware sensors on Apple Silicon.
struct SensorsDetailPopoverView: View {
    let presentation: ThermalPresentation
    @State private var selectedCategory: SensorCategory? = nil

    private var filteredSensors: [SensorReading] {
        if let cat = selectedCategory {
            return presentation.sensors(for: cat)
        }
        return presentation.sensors
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("Cảm biến nhiệt IOHID")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotchTokens.primaryText)
                Spacer()
                Text("\(presentation.sensorCount) cảm biến")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(NotchTokens.secondaryText)
            }

            // Category Filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    categoryButton(nil, title: "Tất cả (\(presentation.sensorCount))")
                    ForEach(SensorCategory.allCases, id: \.self) { cat in
                        let count = presentation.sensors(for: cat).count
                        if count > 0 {
                            categoryButton(cat, title: "\(cat.rawValue) (\(count))")
                        }
                    }
                }
            }

            Divider().overlay(NotchTokens.fill(0.15))

            // Sensors List
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredSensors) { sensor in
                        HStack {
                            Text(sensor.name)
                                .font(.system(size: 11))
                                .foregroundStyle(NotchTokens.primaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(sensor.category.rawValue)
                                .font(.system(size: 9))
                                .foregroundStyle(NotchTokens.secondaryText)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(NotchTokens.fill(0.1)))
                            Text(ThermalFormat.degrees(sensor.temperature))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(temperatureColor(sensor.temperature))
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 4)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(12)
        .frame(width: 310)
        .background(Color(red: 9 / 255, green: 9 / 255, blue: 11 / 255))
    }

    private func categoryButton(_ cat: SensorCategory?, title: String) -> some View {
        let isSelected = selectedCategory == cat
        return Button(action: { selectedCategory = cat }) {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? NotchTokens.primaryText : NotchTokens.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? NotchTokens.fill(0.22) : NotchTokens.fill(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private func temperatureColor(_ temp: Double) -> Color {
        if temp >= 90.0 {
            return Color(red: 1.0, green: 0x45 / 255, blue: 0x3A / 255)
        } else if temp >= 75.0 {
            return Color(red: 1.0, green: 0x9F / 255, blue: 0x0A / 255)
        } else {
            return Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
        }
    }
}
