import NotchUI
import SwiftUI

/// The curve in Settings: whose control the fans are under, the two temperatures, the presets, a small picture of the curve, and
/// what the curve is doing.
struct FanCurveRows: View {
    @Binding var mode: FanMode
    @Binding var start: Int
    @Binding var full: Int
    let runner: FanCurveRunner

    var body: some View {
        let curve = FanCurve(start: start, full: full).normalized
        Group {
            Text("Đường cong quạt").font(.subheadline.weight(.semibold))
            Picker("Chế độ quạt", selection: $mode) {
                ForEach(FanMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if mode == .curve {
                Stepper("Bắt đầu tăng quạt từ \(curve.start) °C", value: startBinding, in: FanCurve.startRange)
                Stepper("Quạt tối đa từ \(curve.full) °C", value: fullBinding, in: FanCurve.fullRange)
                Picker("Mẫu có sẵn", selection: presetBinding) {
                    Text("Của tôi").tag(Optional<FanCurvePreset>.none)
                    ForEach(FanCurvePreset.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                FanCurvePreview(curve: curve)
                    .frame(height: 64)
                    .accessibilityLabel("Đường cong: từ \(curve.start) đến \(curve.full) độ")
            }
            Text(FanCurvePresentation.status(runner.status, mode: mode, curve: curve))
                .font(.caption)
                .foregroundStyle(runner.status.isError ? Tone.critical.color : .secondary)
            Text("Đường cong chỉ chạy khi MyNotch đang mở. Helper luôn trả quạt về chế độ tự động của Apple sau 15 giây nếu không nhận được lệnh mới, và đưa quạt lên tối đa nếu máy nóng quá 95 °C.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The two steppers keep `full` at least five above `start`, whichever the user moves.
    private var startBinding: Binding<Int> {
        Binding(get: { FanCurve(start: start, full: full).normalized.start }, set: { newStart in
            start = newStart
            full = FanCurve(start: newStart, full: full).normalized.full
        })
    }

    private var fullBinding: Binding<Int> {
        Binding(get: { FanCurve(start: start, full: full).normalized.full }, set: { newFull in
            full = newFull
            start = FanCurve(start: start, full: newFull).normalized.start
        })
    }

    private var presetBinding: Binding<FanCurvePreset?> {
        Binding(
            get: { FanCurvePreset.matching(mode: mode, curve: FanCurve(start: start, full: full)) },
            set: { preset in
                guard let preset else { return }
                if let curve = preset.curve {
                    start = curve.start
                    full = curve.full
                    mode = .curve
                } else {
                    mode = .apple
                }
            }
        )
    }
}

extension FanCurveRunner.Status {
    var isError: Bool {
        if case .error = self { true } else { false }
    }
}

/// What the curve says about itself, in words.
nonisolated enum FanCurvePresentation {
    static func status(_ status: FanCurveRunner.Status, mode: FanMode, curve: FanCurve) -> String {
        guard mode == .curve else { return "Quạt đang theo chế độ tự động của Apple." }
        switch status {
        case .off: return "Đường cong đang chờ lần đọc nhiệt độ đầu tiên."
        case .waitingForHelper: return "Đang chờ helper chạy: cài và cho phép helper ở trên."
        case .needsProbe: return "Hãy bấm \"Thử điều khiển quạt\" ở trên trước, để biết máy này cho phép cách nào."
        case .blockedByMacsFanControl: return "Đường cong tạm dừng: thoát Macs Fan Control trước khi điều khiển quạt."
        case let .active(rpm?): return "Đang điều khiển: quạt khoảng \(Int(rpm.rounded())) vòng/phút."
        case .active(nil): return "Chưa cần: Apple đang lo, đường cong sẽ vào từ \(curve.start) °C."
        case let .error(reason): return "Lỗi: \(reason)"
        }
    }
}

/// The curve drawn small: temperature across, from 30 to 100 °C, how much of the fans' range up.
struct FanCurvePreview: View {
    nonisolated static let temperatures = 30.0...100.0

    let curve: FanCurve

    var body: some View {
        let line = NotchTokens.accent
        let guide = NotchTokens.fill(0.2)
        let label = NotchTokens.secondaryText
        VStack(spacing: 2) {
            Canvas { context, size in
                context.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)), with: .color(guide))
                func point(_ temperature: Double) -> CGPoint {
                    let x = (temperature - Self.temperatures.lowerBound) / (Self.temperatures.upperBound - Self.temperatures.lowerBound)
                    return CGPoint(x: x * size.width, y: size.height - 2 - curve.fraction(at: temperature) * (size.height - 6))
                }
                var path = Path()
                var temperature = Self.temperatures.lowerBound
                path.move(to: point(temperature))
                while temperature < Self.temperatures.upperBound {
                    temperature += 1
                    path.addLine(to: point(temperature))
                }
                context.stroke(path, with: .color(line), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                for mark in [Double(curve.start), Double(curve.full)] {
                    let center = point(mark)
                    context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(line))
                }
            }
            HStack {
                Text("30°")
                Spacer()
                Text("\(curve.start)°→\(curve.full)°")
                Spacer()
                Text("100°")
            }
            .font(.system(size: 9))
            .foregroundStyle(label)
        }
    }
}
